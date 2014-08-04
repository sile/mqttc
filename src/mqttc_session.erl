%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc MQTT Session Management Process
%% @private
-module(mqttc_session).

-behaviour(gen_server).
-include_lib("mqttm/include/mqttm.hrl").

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start/1, start_link/1]).
-export([stop/1]).

-export([get_status/1]).
-export([get_client_id/1]).
-export([get_connection/1]).
-export([connect/4]).
-export([disconnect/2]).
-export([publish/4]).
-export([subscribe/3]).
-export([unsubscribe/3]).
-export([ping/1]).

-export_type([owner/0]).
-export_type([start_arg/0]).
-export_type([init_arg/0]).
-export_type([session/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(disconnected_state,
        {
        }).

-record(connecting_state,
        {
          conn :: mqttc_conn:connection(),
          from :: gen_server_from()
        }).

-record(connected_state,
        {
          conn           :: mqttc_conn:connection(),
          active = false :: boolean(),
          queue = []     :: [mqttm:message()]
        }).

-record(disconnecting_state,
        {
          conn  :: mqttc_conn:connection(),
          froms :: [gen_server_from()]
        }).

-record(state,
        {
          client_id                        :: mqttm:client_id(),
          owner                            :: owner(),
          owner_monitor                    :: reference(),
          next_message_id = 0              :: non_neg_integer(),
          id_to_message = splay_tree:new() :: id_to_message(), % XXX: name
          specific = #disconnected_state{} :: status_specific_state()
        }).

-type owner() :: pid().
-type id_to_message() :: splay_tree:tree(mqttm:message_id(), message_data()).
-type message_data() :: {mqttm:message(), Blob::term()}.

-type start_arg() :: init_arg()
                   | {mqttc:session_name_spec(), init_arg()}.
-type init_arg() :: {LinkPid::(pid() | undefined), owner(), mqttm:client_id()}.
        
-type session() :: pid().

-type status_specific_state() :: #disconnected_state{}
                               | #connecting_state{}
                               | #connected_state{}
                               | #disconnecting_state{}.

-type gen_server_from() :: term().

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start(start_arg()) -> {ok, session()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start({Name, Arg}) -> gen_server:start(Name, ?MODULE, Arg, []);
start(Arg)         -> gen_server:start(?MODULE, Arg, []).

-spec start_link(start_arg()) -> {ok, session()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start_link({Name, Arg}) -> gen_server:start_link(Name, ?MODULE, Arg, []);
start_link(Arg)         -> gen_server:start_link(?MODULE, Arg, [{debug, [trace, log]}]).

-spec stop(session()) -> ok.
stop(Pid) ->
    gen_server:cast(Pid, stop).

-spec get_status(session()) -> mqttc:session_status().
get_status(Pid) ->
    gen_server:call(Pid, get_status).

-spec get_client_id(session()) -> mqttm:client_id().
get_client_id(Pid) ->
    gen_server:call(Pid, get_client_id).

-spec get_connection(mqttc:session()) -> mqttc_conn:connection() | undefined.
get_connection(Session) ->
    gen_server:call(Session, get_connection).

-spec connect(session(), mqttc:address(), inet:port_number(), mqttc:connect_opts()) -> ok | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
connect(Pid, Address, Port, Options) ->
    gen_server:call(Pid, {connect, {Address, Port, Options}}).

-spec disconnect(session(), timeout()) -> ok.
disconnect(Pid, Timeout) ->
    gen_server:call(Pid, disconnect, Timeout).

-spec publish(mqttc:session(), mqttm:topic_name(), binary(), mqttc:publish_opts()) -> ok | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
publish(Session, Topic, Payload, Options) ->
    Timeout = proplists:get_value(timeout, Options, 5000),
    gen_server:call(Session, {publish, {Topic, Payload, Options}}, Timeout).

-spec subscribe(mqttc:session(), [{mqttm:topic_name(), mqttm:qos_level()}], mqttc:subscribe_opts()) ->
                       {ok, [mqttm:qos_level()]} | {error, Reason} when % TODO: ok-spec
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
subscribe(Session, TopicList, Options) ->
    Timeout = proplists:get_value(timeout, Options, 5000),
    gen_server:call(Session, {subscribe, {TopicList, Options}}, Timeout).

-spec unsubscribe(mqttc:session(), [mqttm:topic_name()], mqttc:unsubscribe_opts()) -> ok | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
unsubscribe(Session, TopicList, Options) ->
    Timeout = proplists:get_value(timeout, Options, 5000),
    gen_server:call(Session, {unsubscribe, {TopicList, Options}}, Timeout).

-spec ping(mqttc:session()) -> ok.
ping(Session) ->
    gen_server:cast(Session, ping).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init({LinkPid, Owner, ClientId}) when is_pid(LinkPid) ->
    true = link(LinkPid),
    init({undefined, Owner, ClientId});
init({_undefined, Owner, ClientId}) ->
    Monitor = monitor(process, Owner),
    State =
        #state{
           owner         = Owner,
           owner_monitor = Monitor,
           client_id     = ClientId
          },
    {ok, State}.

%% @private
handle_call({publish, Arg}, From, State)     -> handle_publish(Arg, From, State);
handle_call({subscribe, Arg}, From, State)   -> handle_subscribe(Arg, From, State);
handle_call({unsubscribe, Arg}, From, State) -> handle_unsubscribe(Arg, From, State);
handle_call({connect, Arg}, From, State)     -> handle_connect(Arg, From, State);
handle_call(disconnect, From, State)         -> handle_disconnect(From, State);
handle_call(get_status, _, State)            -> handle_get_status(State);
handle_call(get_client_id, _, State)         -> {reply, State#state.client_id, State};
handle_call(get_connection, _, State)        -> {reply, do_get_connection(State), State};
handle_call(Request, From, State)            -> {stop, {unknown_call, Request, From}, State}.

%% @private
handle_cast(ping, State)    -> handle_ping(State);
handle_cast(stop, State)    -> {stop, normal, State};
handle_cast(Request, State) -> {stop, {unknown_cast, Request}, State}.

%% @private
handle_info({mqttc_conn, Pid, connected}, State) -> handle_connected(Pid, State);
handle_info({mqttc_conn, Pid, Msg}, State)       -> handle_message(Pid, Msg, State);
handle_info({'DOWN', _, _, Pid, Reason}, State)  -> handle_down(Pid, Reason, State);
handle_info(Info, State)                         -> {stop, {unknown_info, Info}, State}.

%% @private
terminate(_Reason, State) ->
    _ = case do_get_connection(State) of
            undefined  -> ok;
            Connection -> mqttc_conn:stop(Connection)
        end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec handle_down(pid(), term(), #state{}) -> {stop, Reason::term(), #state{}} | {noreply, #state{}}.
handle_down(Pid, Reason, State = #state{owner = Pid}) ->
    %% owner process is down
    {stop, {shutdown, {owner_down, State#state.owner, Reason}}, State};
handle_down(Pid, Reason, State) ->
    %% connection process is down
    case State#state.specific of
        #disconnected_state{} ->
            {stop, {unknown_process_down, Pid, Reason}, State};
        #connecting_state{from = From} ->
            _ = gen_server:reply(From, {error, {mqtt_error, connect, {disconnected, Reason}}}),
            {noreply, State#state{specific = #disconnected_state{}}};
        #connected_state{} ->
            {noreply, State#state{specific = #disconnected_state{}}};
        #disconnecting_state{froms = Froms} ->
            ok = lists:foreach(fun (F) -> gen_server:reply(F, ok) end, Froms),
            {noreply, State#state{specific = #disconnected_state{}}}
    end.         

-spec handle_get_status(#state{}) -> {reply, mqttc:session_status(), #state{}}.
handle_get_status(State) ->
    {reply, do_get_status(State), State}.

-spec handle_publish(Arg, gen_server_from(), #state{}) -> {noreply, #state{}} |
                                                          {reply, ok | {error, Reason}, #state{}} when
      Arg    :: {mqttm:topic_name(), binary(), mqttc:publish_opts()},
      Reason :: mqttc:mqtt_error_reason().
handle_publish({Topic, Payload, Options}, From, State = #state{specific = #connected_state{}}) ->
    #connected_state{conn = Conn} = State#state.specific,
    RetainFlag = proplists:get_value(retain, Options, false),
    case proplists:get_value(qos, Options, 0) of
        0 ->
            Msg = mqttm:make_publish(Topic, Payload, RetainFlag),
            ok = mqttc_conn:send(Conn, Msg),
            {reply, ok, State};
        QosLevel ->
            %% TODO: handling of publish retry
            #state{next_message_id = MessageId, id_to_message = IdToMsg0} = State,
            Msg = mqttm:make_publish(Topic, Payload, RetainFlag, QosLevel, false, MessageId),
            IdToMsg1 = splay_tree:store(MessageId, {Msg, From}, IdToMsg0),
            ok = mqttc_conn:activate(Conn),
            ok = mqttc_conn:send(Conn, Msg),
            {noreply, State#state{next_message_id = increment_message_id(MessageId), id_to_message = IdToMsg1}}
    end;
handle_publish(_Arg, _From, State) ->
    {reply, {error, {mqtt_error, publish, do_get_status(State)}}, State}.

-spec handle_subscribe(Arg, gen_server_from(), #state{}) -> {noreply, #state{}} |
                                                            {reply, {error, Reason}, #state{}} when
      Arg    :: {[{mqttm:topic_name(), mqttm:qos_level()}], mqttc:subscribe_opts()},
      Reason :: mqttc:mqtt_error_reason().
handle_subscribe({TopicList, _Options}, From, State = #state{specific = #connected_state{}}) ->
    #state{next_message_id = MessageId, id_to_message = IdToMsg0} = State,
    #connected_state{conn = Conn} = State#state.specific,
    Msg = mqttm:make_subscribe(false, MessageId, TopicList),
    IdToMsg1 = splay_tree:store(MessageId, {Msg, From}, IdToMsg0),
    ok = mqttc_conn:activate(Conn),
    ok = mqttc_conn:send(Conn, Msg),
    {noreply, State#state{next_message_id = increment_message_id(MessageId), id_to_message = IdToMsg1}};
handle_subscribe(_Arg, _From, State) ->
    {reply, {error, {mqtt_error, subscribe, do_get_status(State)}}, State}.

-spec handle_unsubscribe(Arg, gen_server_from(), #state{}) -> {noreply, #state{}} |
                                                              {reply, {error, Reason}, #state{}} when
      Arg    :: {[mqttm:topic_name()], mqttc:unsubscribe_opts()},
      Reason :: mqttc:mqtt_error_reason().
handle_unsubscribe({TopicList, _Options}, From, State = #state{specific = #connected_state{}}) ->
    #state{next_message_id = MessageId, id_to_message = IdToMsg0} = State,
    #connected_state{conn = Conn} = State#state.specific,
    Msg = mqttm:make_unsubscribe(false, MessageId, TopicList),
    IdToMsg1 = splay_tree:store(MessageId, {Msg, From}, IdToMsg0),
    ok = mqttc_conn:activate(Conn),
    ok = mqttc_conn:send(Conn, Msg),
    {noreply, State#state{next_message_id = increment_message_id(MessageId), id_to_message = IdToMsg1}};
handle_unsubscribe(_Arg, _From, State) ->
    {reply, {error, {mqtt_error, subscribe, do_get_status(State)}}, State}.

-spec handle_connect(Arg, term(), #state{}) -> {noreply, #state{}} | {reply, {error, Reason}, #state{}} when
      Arg    :: {mqttc:address(), inet:port_number(), mqttc:connect_opts()},
      Reason :: mqttc:mqtt_error_reason().
handle_connect({Address, Port, Options}, From, State = #state{specific = #disconnected_state{}}) ->
    %% TODO: handling of clean session
    #state{client_id = ClientId} = State,
    case mqttc_conn_sup:start_child({self(), {Address, Port, ClientId, Options}}) of
        {error, Reason}  -> {stop, Reason, State};
        {ok, Connection} ->
            _Monitor = monitor(process, Connection),
            Connecting =
                #connecting_state{
                   conn = Connection,
                   from = From
                  },
            {noreply, State#state{specific = Connecting}}
    end;
handle_connect(_Arg, _From, State) ->
    {reply, {error, {mqtt_error, connect, do_get_status(State)}}, State}.

-spec handle_disconnect(gen_server_from(), #state{}) -> {noreply, #state{}} | {reply, ok, #state{}}.
handle_disconnect(_From, State = #state{specific = #disconnected_state{}}) ->
    {reply, ok, State};
handle_disconnect(From, State = #state{specific = #connecting_state{}}) ->
    #connecting_state{from = ConnectRequestor, conn = Conn} = State#state.specific,
    ok = mqttc_conn:stop(Conn),
    _ = gen_server:reply(ConnectRequestor, {error, {mqtt_error, connect, canceled}}),
    Disconnecting =
        #disconnecting_state{conn = Conn, froms = [From]},
    {noreply, State#state{specific = Disconnecting}};
handle_disconnect(From, State = #state{specific = #connected_state{}}) ->
    %% TODO: handle mqtt messages in mailbox
    #connected_state{conn = Conn} = State#state.specific,
    ok = mqttc_conn:stop(Conn),
    Disconnecting =
        #disconnecting_state{conn = Conn, froms = [From]},
    {noreply, State#state{specific = Disconnecting}};
handle_disconnect(From, State = #state{specific = #disconnecting_state{}}) ->
    Disconnecting0 =State#state.specific,
    Disconnecting1 =
        Disconnecting0#disconnecting_state{froms = [From | Disconnecting0#disconnecting_state.froms]},
    {noreply, State#state{specific = Disconnecting1}}.

-spec handle_connected(mqttc_conn:connection(), #state{}) -> {noreply, #state{}} | {stop, Reason::term(), #state{}}.
handle_connected(Conn, State = #state{specific = #connecting_state{conn = Conn}}) ->
    #connecting_state{from = From} = State#state.specific,
    Connected =
        #connected_state{
           conn = Conn
          },
    _ = gen_server:reply(From, ok),
    {noreply, State#state{specific = Connected}};
handle_connected(Pid, State = #state{specific = Specific}) ->
    {stop, {unexpected_connected_notification, Pid, Specific}, State}.

-spec handle_message(mqttc_conn:connection(), mqttm:message(), #state{}) -> {noreply, #state{}}.
handle_message(Conn, Msg = #mqttm_puback{message_id = Id}, State) ->
    case splay_tree:find(Id, State#state.id_to_message) of
        {error, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Msg}, State),
            {noreply, State#state{id_to_message = IdToMsg0}};
        {{ok, {PublishMsg, From}}, IdToMsg0} ->
            case mqttm:get_qos_level(PublishMsg) of
                1 ->
                    _ = gen_server:reply(From, ok),
                    ok = mqttc_conn:inactivate(Conn),
                    IdToMsg1 = splay_tree:erase(Id, IdToMsg0),
                    {noreply, State#state{id_to_message = IdToMsg1}};
                _ ->
                    ok = notify_error(recv, {unexpected_message, Msg}, State),
                    {noreply, State#state{id_to_message = IdToMsg0}}
            end
    end;
handle_message(Conn, Msg = #mqttm_pubrec{message_id = Id}, State) ->
    case splay_tree:find(Id, State#state.id_to_message) of
        {error, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Msg}, State),
            {noreply, State#state{id_to_message = IdToMsg0}};
        {{ok, {PublishMsg, From}}, IdToMsg0} ->
            case mqttm:get_qos_level(PublishMsg) of
                2 ->
                    ok = mqttc_conn:send(Conn, mqttm:make_pubrel(false, Id)),
                    IdToMsg1 = splay_tree:store(Id, {Msg, From}, IdToMsg0),
                    {noreply, State#state{id_to_message = IdToMsg1}};
                _ ->
                    ok = notify_error(recv, {unexpected_message, Msg}, State),
                    {noreply, State#state{id_to_message = IdToMsg0}}
            end
    end;
handle_message(Conn, Msg = #mqttm_pubcomp{message_id = Id}, State) ->
    case splay_tree:find(Id, State#state.id_to_message) of
        {{ok, {#mqttm_pubrec{}, From}}, IdToMsg0} ->
            _ = gen_server:reply(From, ok),
            ok = mqttc_conn:inactivate(Conn),
            IdToMsg1 = splay_tree:erase(Id, IdToMsg0),
            {noreply, State#state{id_to_message = IdToMsg1}};
        {_, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Msg}, State),
            {noreply, State#state{id_to_message = IdToMsg0}}
    end;
handle_message(Conn, Msg = #mqttm_publish{message_id = Id}, State) ->
    case mqttm:get_qos_level(Msg) of
        0 ->
            ok = notify_error(recv, {unexpected_message, Msg}, State), % XXX:
            {noreply, State};
        1 ->
            ok = notify_error(recv, {unexpected_message, Msg}, State), % XXX:
            ok = mqttc_conn:send(Conn, mqttm:make_puback(Id)),
            {noreply, State};
        2 ->
            #state{id_to_message = IdToMsg0} = State,
            IdToMsg1 = splay_tree:store({recv, Id}, Msg, IdToMsg0), % XXX:
            ok = mqttc_conn:send(Conn, mqttm:make_pubrec(Id)),
            {noreply, State#state{id_to_message = IdToMsg1}}
    end;
handle_message(Conn, Msg = #mqttm_pubrel{message_id = Id}, State) ->
    case splay_tree:find({recv, Id}, State#state.id_to_message) of
        {{ok, #mqttm_publish{} = Publish}, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Publish}, State), % XXX:
            ok = mqttc_conn:send(Conn, mqttm:make_pubcomp(Id)),
            IdToMsg1 = splay_tree:erase({recv, Id}, IdToMsg0),
            {noreply, State#state{id_to_message = IdToMsg1}};
        {_, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Msg}, State),
            {noreply, State#state{id_to_message = IdToMsg0}}
    end;
handle_message(Conn, Msg = #mqttm_suback{message_id = Id}, State) ->
    case splay_tree:find(Id, State#state.id_to_message) of
        {{ok, {#mqttm_subscribe{payload = Payload}, From}}, IdToMsg0} ->
            Result = [{Name, Qos} || {{Name, _}, Qos} <- lists:zip(Payload, Msg#mqttm_suback.payload)],
            _ = gen_server:reply(From, {ok, Result}),
            ok = mqttc_conn:inactivate(Conn),
            IdToMsg1 = splay_tree:erase(Id, IdToMsg0),
            {noreply, State#state{id_to_message = IdToMsg1}};
        {_, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Msg}, State),
            {noreply, State#state{id_to_message = IdToMsg0}}
    end;
handle_message(Conn, Msg = #mqttm_unsuback{message_id = Id}, State) ->
    case splay_tree:find(Id, State#state.id_to_message) of
        {{ok, {#mqttm_unsubscribe{}, From}}, IdToMsg0} ->
            _ = gen_server:reply(From, ok),
            ok = mqttc_conn:inactivate(Conn),
            IdToMsg1 = splay_tree:erase(Id, IdToMsg0),
            {noreply, State#state{id_to_message = IdToMsg1}};
        {_, IdToMsg0} ->
            ok = notify_error(recv, {unexpected_message, Msg}, State),
            {noreply, State#state{id_to_message = IdToMsg0}}
    end;
handle_message(_Conn, Msg, State) ->
    ok = notify_error(recv, {unexpected_message, Msg}, State),
    {noreply, State}.

-spec handle_ping(#state{}) -> {noreply, #state{}}.
handle_ping(State = #state{specific = #connected_state{conn = Conn}}) ->
    ok = mqttc_conn:activate(Conn),
    ok = mqttc_conn:send(Conn, mqttm:make_pingreq()),
    {noreply, State};
handle_ping(State) ->
    ok = notify_error(ping, get_status(State), State),
    {noreply, State}.

-spec do_get_status(#state{}) -> mqttc:session_status().
do_get_status(#state{specific = Specific}) ->
    case Specific of
        #disconnected_state{}  -> disconnected;
        #connecting_state{}    -> connecting;
        #connected_state{}     -> connected;
        #disconnecting_state{} -> disconnecting
    end.

-spec do_get_connection(#state{}) -> undefined | mqttc_conn:connection().
do_get_connection(#state{specific = Specific}) ->
    case Specific of
        #disconnected_state{}             -> undefined;
        #connecting_state{conn = Conn}    -> Conn;
        #connected_state{conn = Conn}     -> Conn;
        #disconnecting_state{conn = Conn} -> Conn
    end.

-spec increment_message_id(mqttm:message_id()) -> mqttm:message_id().
increment_message_id(Id) -> (Id + 1) rem 16#10000.

-spec notify_error(atom(), term(), #state{}) -> ok.
notify_error(Tag, Reason, State) ->
    _ = State#state.owner ! {mqtt_error, Tag, Reason},
    ok.
