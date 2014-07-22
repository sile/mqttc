%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
%% @private
-module(mqttc_connection).

-behaviour(gen_server).
-include_lib("mqttm/include/mqttm.hrl").

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/1]).

-export_type([start_arg/0]).
-export_type([connect_arg/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(state,
        {
          session_pid      :: pid(),
          socket           :: inet:socket(),
          recv_data = <<>> :: binary()
        }).

-type start_arg()   :: {pid(), connect_arg()}.
-type connect_arg() :: {mqttc:address(), inet:port_number(), mqttm:client_id(), mqttc:connect_opts()}.

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start_link(start_arg()) -> {ok, pid()} | {error, Reason::term()}.
start_link(Arg) ->
    gen_server:start_link(?MODULE, Arg, []).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init(Arg = {SessionPid, _}) ->
    true = link(SessionPid),
    {ok, Arg, 0}.

%% @private
handle_call(Request, From, State) ->
    {stop, {unknown_call, Request, From}, State}.

%% @private
handle_cast(Request, State) ->
    {stop, {unknown_cast, Request}, State}.

%% @private
handle_info(timeout, {SessionPid, ConnectArg}) ->
    case do_connect(ConnectArg) of
        {error, Reason} ->
            ok = notify(SessionPid, {connect, {error, Reason}}),
            {stop, normal, not_initialized};
        {ok, Socket}    ->
            ok = notify(SessionPid, {connect, ok}),
            State =
                #state{
                   session_pid = SessionPid,
                   socket      = Socket
                  },
            {noreply, State}
    end;
handle_info(Info, State) ->
    {stop, {unknown_info, Info}, State}.

%% @private
terminate(_Reason, State = #state{}) ->
    ok = tcp:close(State#state.socket),
    ok;
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec notify(pid(), term()) -> ok.
notify(Pid, Message) ->
    _ = Pid ! {mqtt_connection, self(), Message},
    ok.

-spec do_connect(connect_arg()) -> {ok, inet:socket()} | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
do_connect({Address, Port, ClientId, Options}) ->
    case do_tcp_connect(Address, Port, Options) of
        {error, Reason} -> {error, Reason};
        {ok, Socket}    ->
            case do_mqtt_connect(Socket, ClientId, Options) of
                {error, Reason} -> {error, Reason};
                ok              -> {ok, Socket}
            end
    end.

-spec do_tcp_connect(mqttc:address(), inet:port_number(), mqttc:connect_opts()) ->
                            {ok, inet:socket()} | {error, mqttc:tcp_error_reason()}.
do_tcp_connect(Address0, Port, Options) ->
    Address1 =
        case is_binary(Address0) of
            true  -> binary_to_list(Address0);
            false -> Address0
        end,
    Timeout = proplists:get_value(tcp_timeout, Options, 5000),
    TcpOptions = proplists:get_value(tcp_connect_opts, Options, []),
    case gen_tcp:connect(Address1, Port, [{active, false}, binary] ++ TcpOptions, Timeout) of
        {error, Reason} -> {error, {tcp_error, connect, Reason}};
        {ok, Socket}    -> {ok, Socket}
    end.

-spec do_mqtt_connect(inet:socket(), mqttm:client_id(), mqttc:connect_opts()) -> ok | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
do_mqtt_connect(Socket, ClientId, Options) ->
    Timeout = proplists:get_value(tcp_timeout, Options, 5000),
    ConnectMsg = mqttm:make_connect(ClientId, Options),
    case gen_tcp:send(Socket, mqttm:encode(ConnectMsg)) of
        {error, Reason} -> {error, {tcp_error, send, Reason}};
        ok              ->
            ConnAckMessageByteSize = 4,
            case gen_tcp:recv(Socket, ConnAckMessageByteSize, Timeout) of
                {error, Reason} -> {error, {tcp_error, recv, Reason}};
                {ok, Bytes}     ->
                    {[ConnackMsg = #mqttm_connack{}], <<>>} = mqttm:decode(Bytes), % XXX: error handling
                    case ConnackMsg#mqttm_connack.return_code of
                        0    -> ok;
                        Code -> {error, {mqtt_error, connect, {rejected, Code}}}
                    end
            end
    end.
