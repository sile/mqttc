%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc supervisor for client MQTT session processes
%% @private
-module(mqttc_session).

-behaviour(gen_server).
-include_lib("mqttm/include/mqttm.hrl").

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/1]).
-export([close/1]).
-export([publish/2]).
-export([ping/1]).
-export([subscribe/2]).
-export([unsubscribe/2]).

-export_type([start_arg/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(state,
        {
          socket :: inet:socket(),
          client_id :: mqttm:client_id(),
          controlling_process :: {pid(), reference()},
          message_id = 0 :: mqttm:message_id(),
          buffer = <<"">> :: binary(),
          id_to_msg = gb_trees:empty() :: gb_trees:tree(mqttm:message_id(), {mqttm:message(), term()})
        }).

-type start_arg() :: {pid(), mqttc:adddres(), inet:port_number(), mqttm:client_id(), [mqttc:connect_option()]}.

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start_link(start_arg()) -> {ok, pid()} | {error, Reason::term()}.
start_link(Arg) ->
    {_, _, _, _, Options} = Arg,
    Timeout = proplists:get_value(timeout, Options, infinity),
    case gen_server:start_link(?MODULE, Arg, [{timeout, Timeout}, {debug, [trace]}]) of
        {error, {shutdown, Reason}} -> {error, Reason};
        Other                       -> Other
    end.

-spec close(pid()) -> ok.
close(Pid) ->
    gen_server:cast(Pid, close).

-spec publish(pid(), mqttm:publish_message()) -> ok.
publish(Pid, PublishMsg) ->
    gen_server:cast(Pid, {publish, PublishMsg}).

-spec ping(pid()) -> ok.
ping(Pid) ->
    gen_server:cast(Pid, {ping}).

-spec subscribe(pid(), mqttm:subscribe_message()) -> {ok, [mqttm:qos_level()]} | {error, Reason::term()}.
subscribe(Pid, Msg) ->
    gen_server:call(Pid, {subscribe, Msg}).

-spec unsubscribe(pid(), mqttm:unsubscribe_message()) -> ok.
unsubscribe(Pid, Msg) ->
    gen_server:cast(Pid, {unsubscribe, Msg}).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init({Pid, Address, Port, ClientId, Options}) ->
    %% XXX: init内でブロッキングする処理は避ける(or supervisor以外のモジュール経由で起動する)
    case mqttc_lib:connect(Address, Port, ClientId, Options) of
        {error, Reason} -> {stop, {shutdown, Reason}};
        {ok, Socket}    ->
            Monitor = monitor(process, Pid),
            ok = inet:setopts(Socket, [{active, once}]), %% TODO: error handling
            State =
                #state{
                   socket = Socket,
                   client_id = ClientId,
                   controlling_process = {Pid, Monitor}
                  },
            {ok, State}
    end.

%% @private
handle_call({subscribe, Msg}, From, State) ->
    case do_subscribe(Msg, From, State) of
        {{error, Reason}, State1} -> {stop, {error, Reason}, Reason, State1};
        {ok, State1}              -> {noreply, State1}
    end;
handle_call(Request, From, State) ->
    {stop, {unknown_call, Request, From}, State}.

%% @private
handle_cast({publish, PublishMsg}, State0) ->
    case do_publish(PublishMsg, State0) of % TODO: qos > 0 の場合は終了をクライアントに通知した方がよいかもしれない
        {{error, Reason}, State1} -> {stop, Reason, State1};
        {ok, State1}              -> {noreply, State1}
    end;

handle_cast({ping}, State0) ->
    mqttc_lib:ping(State0#state.socket),
    {noreply, State0};


handle_cast({unsubscribe, Msg}, State0) ->
    case do_unsubscribe(Msg, State0) of
        {{error, Reason}, State1} -> {stop, Reason, State1};
        {ok, State1}              -> {noreply, State1}
    end;
handle_cast(close, State) ->
    {stop, normal, State};
handle_cast(Request, State) ->
    {stop, {unknown_cast, Request}, State}.

%% @private
handle_info({tcp, _, Data}, State0) ->
    case handle_recv(<<(State0#state.buffer)/binary, Data/binary>>, State0) of
        {{error, Reason}, State1} -> {stop, Reason, State1};
        {ok, State1}              -> {noreply, State1}
    end;
handle_info({tcp_error, _, Reason}, State) ->
    {stop, {tcp_error, Reason}, State};
handle_info({tcp_closed, _}, State) ->
    {stop, tcp_closed, State};
handle_info({'DOWN', _, _, _, _}, State) ->
    {stop, normal, State};
handle_info(Info, State) ->
    {stop, {unknown_info, Info}, State}.

%% @priavte
terminate(_Reason, State) ->
    _ = mqttc_lib:disconnect(State#state.socket),
    _ = gen_tcp:close(State#state.socket),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec do_publish(mqttm:publish_message(), #state{}) -> {Result, #state{}} when
      Result :: ok | {error, Reason::term()}.
do_publish(PublishMsg0, State0) ->
    {PublishMsg1, State1} =
        case PublishMsg0#mqttm_publish.message_id of
            undefined -> {PublishMsg0, State0};
            _         ->
                NextMessageId = (State0#state.message_id + 1) rem 16#10000,
                {PublishMsg0#mqttm_publish{message_id = NextMessageId}, State0#state{message_id = NextMessageId}}
        end,
    Result = mqttc_lib:publish(State1#state.socket, PublishMsg1),
    {Result, State1}.


-spec do_subscribe(mqttm:subscribe_message(), term(), #state{}) -> {Result, #state{}} when
      Result :: ok | {error, Reason::term()}.
do_subscribe(Msg0, From, State0) ->
    NextMessageId = (State0#state.message_id + 1) rem 16#10000,
    Msg1 = Msg0#mqttm_subscribe{message_id = NextMessageId},
    State1 = State0#state{
               message_id = NextMessageId,
               id_to_msg = gb_trees:enter(NextMessageId, {Msg1, From}, State0#state.id_to_msg)
              },
    Result = mqttc_lib:subscribe(State1#state.socket, Msg1),
    {Result, State1}.

-spec do_unsubscribe(mqttm:unsubscribe_message(), #state{}) -> {Result, #state{}} when
      Result :: ok | {error, Reason::term()}.
do_unsubscribe(Msg0, State0) ->
    NextMessageId = (State0#state.message_id + 1) rem 16#10000,
    Msg1 = Msg0#mqttm_unsubscribe{message_id = NextMessageId},
    State1 = State0#state{message_id = NextMessageId},
    Result = mqttc_lib:unsubscribe(State1#state.socket, Msg1),
    {Result, State1}.

-spec handle_recv(binary(), #state{}) -> {Result, #state{}} when
      Result :: ok | {error, Reason::term()}.
handle_recv(Data0, State0) ->
    {Messages, Data1} = mqttm:decode(Data0),
    ok = inet:setopts(State0#state.socket, [{active, once}]), % XXX:
    handle_messages(Messages, State0#state{buffer = Data1}).

-spec handle_messages([mqttm:message()], #state{}) -> {Result, #state{}} when
      Result :: ok | {error, Reason::term()}.
handle_messages([], State)        -> {ok, State};
handle_messages([M | Ms], State0) -> 
    case handle_message(M, State0) of
        {{error, Reason}, State1} -> {{error, Reason}, State1};
        {ok, State1}              -> handle_messages(Ms, State1)
    end.

-spec handle_message(mqttm:message(), #state{}) -> {Result, #state{}} when
      Result :: ok | {error, Reason::term()}.
handle_message(#mqttm_publish{topic_name = Topic, payload = Payload}, State) ->
    %% TODO: QoSに応じたハンドリング
    #state{controlling_process = {Pid, _}} = State,
    _ = Pid ! {mqtt, self(), Topic, Payload},
    {ok, State};
handle_message(#mqttm_puback{}, State0) ->
    %% TODO: ID確認
    {ok, State0};
handle_message(#mqttm_pubrec{message_id = MessageId}, State0) ->
    %% TODO: ID確認
    {mqttc_lib:pubrel(State0#state.socket, MessageId), State0};
handle_message(#mqttm_pubcomp{}, State0) ->
    %% TODO: ID確認
    {ok, State0};

handle_message(#mqttm_pingresp{}, State0) ->
    %% TODO: ID確認
    {ok, State0};

handle_message(#mqttm_suback{message_id = Id, payload = QosList}, State0) ->
    case gb_trees:lookup(Id, State0#state.id_to_msg) of
        none               -> {{error, {unexpected_suback_message_id, Id}}, State0};
        {value, {_, From}} ->
            _ = gen_server:reply(From, {ok, QosList}),
            State1 = State0#state{id_to_msg = gb_trees:delete(Id, State0#state.id_to_msg)},
            {ok, State1}
    end;
handle_message(#mqttm_unsuback{}, State0) ->
    {ok, State0};
handle_message(Message, State) ->
    {{error, {unexpected_mqtt_message, Message}}, State}.
