%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
%% @private
-module(mqttc_session).

-behaviour(gen_fsm).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/1]).
-export([stop/1]).
-export([get_status/1]).
-export([get_client_id/1]).
-export([connect/5]).

-export_type([start_arg/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_fsm' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([disconnected/2, disconnected/3, connecting/2, connecting/3, connected/2, connected/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(common_state,
        {
          client_id           :: mqttm:client_id(),
          controlling_pid     :: pid(),
          controlling_monitor :: reference()
        }).

-record(disconnected_state,
        {
        }).

-record(connecting_state,
        {
          caller             :: gen_fsm_caller(),
          connection_pid     :: pid(),
          connection_monitor :: reference()
        }).

-record(connected_state,
        {
          connection_pid     :: pid(),
          connection_monitor :: reference()
        }).

-type start_arg() :: {mqttc:session_name_spec() | undefined, ({link, pid()} | pid()), mqttm:client_id()}.

-type state() :: {#common_state{}, specific_state()}.
-type specific_state() :: #disconnected_state{} | #connecting_state{} | #connected_state{}.

-type gen_fsm_caller() :: any().

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start_link(start_arg()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start_link({undefined, LinkPid, ClientId}) ->
    gen_fsm:start_link(?MODULE, {LinkPid, ClientId}, []);
start_link({Name, LinkPid, ClientId}) ->
    gen_fsm:start_link(Name, ?MODULE, {LinkPid, ClientId}, []).

-spec stop(mqttc:session()) -> ok.
stop(Session) ->
    gen_fsm:send_all_state_event(Session, stop).

-spec get_status(mqttc:session()) -> mqttc:session_status().
get_status(Session) ->
    gen_fsm:sync_send_all_state_event(Session, get_status).

-spec get_client_id(mqttc:session()) -> mqttm:client_id().
get_client_id(Session) ->
    gen_fsm:sync_send_all_state_event(Session, get_client_id).

-spec connect(mqttc:session(), mqttc:address(), inet:port_number(), mqttc:connect_opts(), timeout()) -> ok | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
connect(Session, Address, Port, Options, Timeout) ->
    gen_fsm:sync_send_event(Session, {mqtt_request, connect, {Address, Port, Options}}, Timeout).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_fsm' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init({{link, LinkPid}, ClientId}) when is_pid(LinkPid) ->
    true = link(LinkPid),
    init({LinkPid, ClientId});
init({ControllingPid, ClientId}) ->
    Monitor = monitor(process, ControllingPid),
    CommonState =
        #common_state{
           client_id           = ClientId,
           controlling_pid     = ControllingPid,
           controlling_monitor = Monitor
          },
    {ok, disconnected, {CommonState, #disconnected_state{}}}.

%% @private
disconnected(Event, State) ->
    handle_event_default(Event, disconnected, State).

%% @private
disconnected({mqtt_request, connect, Arg}, From, State0) ->
    State1 = start_connecting(Arg, From, State0),
    {next_state, connecting, State1};
disconnected(Event, From, State) ->
    handle_sync_event_default(Event, From, disconnected, State).

%% @private
connecting(Event, State) ->
    handle_event_default(Event, connecting, State).

%% @private
connecting(Event, From, State) ->
    handle_sync_event_default(Event, From, connecting, State).

%% @private
connected(Event, State) ->
    handle_event_default(Event, connected, State).

%% @private
connected(Event, From, State) ->
    handle_sync_event_default(Event, From, connected, State).

%% @private
handle_event(stop, _StateName, State) ->
    {stop, normal, State};
handle_event(Event, StateName, State) ->
    {stop, {unknown_all_state_event, Event, StateName}, State}.

%% @private
handle_sync_event(get_status, _From, StateName, State) ->
    {reply, StateName, StateName, State};
handle_sync_event(get_client_id, _From, StateName, State = {Common, _}) ->
    {reply, Common#common_state.client_id, StateName, State};
handle_sync_event(Event, From, StateName, State) ->
    {stop, {unknown_sync_all_state_event, Event, From, StateName}, State}.

%% @private
handle_info({mqtt_connection, Pid, {connect, Result}}, connecting, {Common, Specific0 = #connecting_state{connection_pid = Pid}}) ->
    {Next, Specific1} =
        case Result of
            ok ->
                {connected,
                 #connected_state{
                    connection_pid     = Specific0#connecting_state.connection_pid,
                    connection_monitor = Specific0#connecting_state.connection_monitor
                   }};
            {error, _} ->
                _ = demonitor(Specific0#connecting_state.connection_monitor, [flush]),
                {disconnected,
                 #disconnected_state{}}
        end,
    _ = gen_fsm:reply(Specific0#connecting_state.caller, Result),
    {next_state, Next, {Common, Specific1}};
handle_info({'DOWN', _, _, Pid, Reason}, _StateName, State = {#common_state{controlling_pid = Pid}, _}) ->
    {stop, {shutdown, {controlling_process_down, Pid, Reason}}, State};
handle_info(Info, StateName, State) ->
    {stop, {unknown_info, Info, StateName}, State}.

%% @private
%% terminate(Reason, connecting, {Common, Specific}) ->
%%     ok = gen_tcp:close(Specific#connecting_state.socket),
%%     terminate(Reason, disconnected, {Common, #disconnected_state{}});
%% terminate(Reason, connected, {Common, Specific}) ->
%%     ok = gen_tcp:close(Specific#connected_state.socket),
%%     terminate(Reason, disconnected, {Common, #disconnected_state{}});
terminate(_Reason, _StateName, _State) ->
    ok.

%% @private
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec handle_sync_event_default(term(), term(), atom(), state()) -> {reply, term(), atom(), state()} |
                                                                    {stop, term(), state()}.
handle_sync_event_default({mqtt_request, Command, _Arg}, _From, StateName, State) ->
    {reply, {error, {mqtt_error, Command, StateName}}, StateName, State};
handle_sync_event_default(Event, From, StateName, State) ->
    {stop, {unknown_sync_event, Event, From, StateName}, State}.

-spec handle_event_default(term(), atom(), state()) -> {next_state, atom(), state()} |
                                                       {stop, term(), state()}.
handle_event_default({mqtt_async_request, From, Command, _Arg}, StateName, State) ->
    ok = notify(From, {mqtt_error, Command, StateName}), 
    {next_state, StateName, State};
handle_event_default(Event, StateName, State) ->
    {stop, {unknown_event, Event, StateName}, State}.

-spec notify(mqttc:from()|pid(), term()) -> ok.
notify({Pid, Tag}, Message) ->
    _ = Pid ! {mqtt, Tag, self(), Message},
    ok;
notify(Pid, Message) ->
    _ = Pid ! {mqtt, self(), Message},
    ok.

-spec start_connecting({mqttc:address(), inet:port_number(), mqttc:connect_opts()}, gen_fsm_caller(), state()) -> state().
start_connecting({Address, Port, Options}, Caller, {Common, #disconnected_state{}}) ->
    {ok, Connection} = mqttc_connection_sup:start_child({self(), {Address, Port, Common#common_state.client_id, Options}}),
    Monitor = monitor(process, Connection),
    Specific =
        #connecting_state{
           caller             = Caller,
           connection_pid     = Connection,
           connection_monitor = Monitor
          },
    {Common, Specific}.

%% -spec do_disconnect(state()) -> state().
%% do_disconnect(State = {_, #disconnected_state{}}) -> State;
%% do_disconnect({Common, Specific}) ->
%%     Socket =
%%         case Specific of
%%             #connecting_state{} ->
%%                 Specific#connecting_state.socket;
%%             #connected_state{} ->
%%                 gen_tcp:send(
%%                 Specific#connected_state.socket
%%         end,
%%     ok = gen_tcp:close(Socket),
%%     ok = flush_tcp_data(Socket),
%%     {Common#common_state{recv_data = <<>>}, #disconnected_state{}}.

%% -spec flush_tcp_data(inet:socket()) -> ok.
%% flush_tcp_data(Socket) ->
%%     receive
%%         {tcp, Socket, _} -> flush_tcp_data(Socket)
%%     after 0 -> ok
%%     end.
