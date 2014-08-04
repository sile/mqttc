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
-export([send/2]).
-export([activate/1, inactivate/1]).
-export([get_socket/1]).

-export_type([start_arg/0]).
-export_type([connect_arg/0]).
-export_type([connection/0]).
-export_type([owner/0]).
-export_type([recv_tag/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(state,
        {
          owner            :: owner(),
          socket           :: inet:socket(),
          recv_data = <<>> :: binary(),
          active = 0       :: non_neg_integer() % XXX: name 
        }).

-type start_arg()   :: {owner(), connect_arg()}.
-type connect_arg() :: {mqttc:address(), inet:port_number(), mqttm:client_id(), mqttc:connect_opts()}.

-type owner() :: pid().
-type connection() :: pid().

-type recv_tag() :: term().

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

-spec send(connection(), mqttm:message()) -> ok.
send(Pid, Message) ->
    gen_server:cast(Pid, {send, Message}).

-spec activate(connection()) -> ok.
activate(Pid) ->
    gen_server:cast(Pid, {active, true}).

-spec inactivate(connection()) -> ok.
inactivate(Pid) ->
    gen_server:cast(Pid, {active, false}).

%% for debug purpose
-spec get_socket(connection()) -> inet:socket().
get_socket(Pid) ->
    gen_server:call(Pid, get_socket).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init(Arg) -> {ok, Arg, 0}.

%% @private
handle_call(get_socket, _From, State) -> {reply, State#state.socket, State};
handle_call(Request, From, State)     -> {stop, {unknown_call, Request, From}, State}.

%% @private
handle_cast({send, Arg}, State)   -> handle_send(Arg, State);
handle_cast({active, Arg}, State) -> handle_active(Arg, State);
handle_cast(stop, State)          -> {stop, normal, State};
handle_cast(Request, State)       -> {stop, {unknown_cast, Request}, State}.

%% @private
handle_info({tcp, _, Data}, State)            -> handle_recv(Data, State);
handle_info({tcp_error, _, Reason}, State)    -> {stop, {shutdown, {tcp_error, recv, Reason}}, State};
handle_info({tcp_closed, _}, State)           -> {stop, {shutdown, {tcp_error, recv, closed}}, State};
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
            ok = notify(connected, State),
            {noreply, State}
    end.

-spec handle_owner_down(term(), #state{}) -> {stop, Reason::term(), #state{}}.
handle_owner_down(Reason, State) ->
    {stop, {shutdown, {owner_down, State#state.owner, Reason}}, State}.

-spec handle_send(mqttm:message(), #state{}) -> {noreply, #state{}} | {stop, Reason::term(), #state{}}.
handle_send(Message, State) ->
    case gen_tcp:send(State#state.socket, mqttm:encode(Message)) of
        {error, Reason} -> {stop, Reason, State};
        ok              -> {noreply, State}
    end.

-spec handle_active(boolean(), #state{}) -> {noreply, #state{}} | {stop, Reason::term(), #state{}}.
handle_active(true, State = #state{active = N}) when N > 0 ->
    {noreply, State#state{active = N + 1}};
handle_active(false, State = #state{active = N}) when N =/= 1 ->
    {noreply, State#state{active = max(0, N - 1)}};
handle_active(Activeness, State = #state{active = Count}) ->
    Delta = case Activeness of true -> 1; false -> -1 end,
    case inet:setopts(State#state.socket, [{active, Activeness}]) of
        ok              -> handle_recv(<<>>, State#state{active = Count + Delta});
        {error, Reason} -> {stop, {shutdown, {tcp_error, setopts, Reason}}, State}
    end.

-spec handle_recv(binary(), #state{}) -> {noreply, #state{}}.
handle_recv(Data0, State) ->
    Data1 = <<(State#state.recv_data)/binary, Data0/binary>>,
    case State#state.active of
        0 -> {noreply, State#state{recv_data = Data1}};
        _ ->
            {Messages, Data2} = mqttm:decode(Data1),
            ok = lists:foreach(fun (M) -> notify(M, State) end, Messages),
            {noreply, State#state{recv_data = Data2}}
    end.

-spec notify(term(), #state{}) -> ok.
notify(Message, #state{owner = Owner}) ->
    _ = Owner ! {?MODULE, self(), Message},
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
