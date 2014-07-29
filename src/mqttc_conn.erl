%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc MQTT TCP Connection Management Process
%% @private
-module(mqttc_conn).

-behaviour(gen_server).
-include_lib("mqttm/include/mqttm.hrl").

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start/1, start_link/1]).
-export([stop/1]).

-export_type([start_arg/0]).
-export_type([connect_arg/0]).
-export_type([connection/0]).
-export_type([owner/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(state,
        {
          owner            :: owner(),
          socket           :: inet:socket(),
          recv_data = <<>> :: binary()
        }).

-type start_arg()   :: {owner(), connect_arg()}.
-type connect_arg() :: {mqttc:address(), inet:port_number(), mqttm:client_id(), mqttc:connect_opts()}.

-type owner() :: pid().
-type connection() :: pid().

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start(start_arg()) -> {ok, connection()} | {error, Reason::term()}.
start(Arg) ->
    gen_server:start(?MODULE, Arg, []).

-spec start_link(start_arg()) -> {ok, connection()} | {error, Reason::term()}.
start_link(Arg) ->
    gen_server:start_link(?MODULE, Arg, []).

-spec stop(connection()) -> ok.
stop(Pid) ->
    gen_server:cast(Pid, stop).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init(Arg) -> {ok, Arg, 0}.

%% @private
handle_call(Request, From, State) -> {stop, {unknown_call, Request, From}, State}.

%% @private
handle_cast(stop, State)    -> {stop, normal, State};
handle_cast(Request, State) -> {stop, {unknown_cast, Request}, State}.

%% @private
handle_info({'DOWN', _, _, _, Reason}, State) -> handle_owner_down(Reason, State);
handle_info(timeout, Arg)                     -> handle_initialize(Arg);
handle_info(Info, State)                      -> {stop, {unknown_info, Info}, State}.

%% @private
terminate(_Reason, State = #state{}) -> disconnect(State);
terminate(_Reason, _State)           -> ok.

%% @private
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec handle_initialize(start_arg()) -> {noreply, #state{}} | {stop, Reason::term(), {start_arg, start_arg()}}.
handle_initialize(Arg = {Owner, ConnectArg}) ->
    case connect(ConnectArg) of
        {error, Reason} -> {stop, {shutdown, Reason}, {start_arg, Arg}};
        {ok, Socket}    ->
            _Monitor = monitor(process, Owner),
            State = #state{owner = Owner, socket = Socket},
            ok = notify(State, connected),
            {noreply, State}
    end.

-spec handle_owner_down(term(), #state{}) -> {stop, Reason::term(), #state{}}.
handle_owner_down(Reason, State) ->
    {stop, {shutdown, {owner_down, State#state.owner, Reason}}, State}.

-spec notify(#state{}, term()) -> ok.
notify(#state{owner = Owner}, Message) ->
    _ = Owner ! {mqtt_connection, self(), Message},
    ok.

-spec connect(connect_arg()) -> {ok, inet:socket()} | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
connect({Address, Port, ClientId, Options}) ->
    ExpiryTime = mqttc_tcp_lib:timeout_to_expiry_time(proplists:get_value(timeout, Options, 5000)),
    TcpOptions = proplists:get_value(tcp_connect_opts, Options, []),
    case mqttc_tcp_lib:connect(Address, Port, [{active, false}, binary | TcpOptions], ExpiryTime) of
        {error, Reason} -> {error, {tcp_error, connect, Reason}};
        {ok, Socket}    ->
            case mqtt_connect(Socket, ClientId, Options, ExpiryTime) of
                {error, Reason} -> {error, Reason};
                ok              -> {ok, Socket}
            end
    end.

-spec mqtt_connect(inet:socket(), mqttm:client_id(), mqttc:connect_opts(), mqttc_tcp_lib:expiry_time()) ->
                          ok | {error, Reason} when
      Reason :: mqttc:tcp_error_reason() | mqttc:mqtt_error_reason().
mqtt_connect(Socket, ClientId, Options, ExpiryTime) ->
    ConnectMsg = mqttm:make_connect(ClientId, Options),
    case mqttc_tcp_lib:send(Socket, mqttm:encode(ConnectMsg), ExpiryTime) of
        {error, Reason} -> {error, {tcp_error, send, Reason}};
        ok              ->
            ConnAckMessageByteSize = 4,
            case mqttc_tcp_lib:recv(Socket, ConnAckMessageByteSize, ExpiryTime) of
                {error, Reason} -> {error, {tcp_error, recv, Reason}};
                {ok, Bytes}     ->
                    case mqttm:decode(Bytes) of % TODO: use mqttm:try_decode/1
                        {[#mqttm_connack{return_code = Code}], Remainings} ->
                            <<>> = Remainings,
                            case Code of
                                0    -> ok;
                                Code -> {error, {mqtt_error, connect, {rejected, Code}}}
                            end;
                        {Messages, _} ->
                            {error, {mqtt_error, connect,
                                     {unexpected_response, [{bytes, Bytes}, {messages, Messages}]}}}
                    end
            end
    end.

-spec disconnect(#state{}) -> ok.
disconnect(State) ->
    _ = gen_tcp:send(State#state.socket, mqttm:encode(mqttm:make_disconnect())),
    _ = gen_tcp:close(State#state.socket),
    ok.
