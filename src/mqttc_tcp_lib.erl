%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TCP Utility Functions
%% @private
-module(mqttc_tcp_lib).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([timeout_to_expiry_time/1]).
-export([connect/4]).
-export([send/3]).
-export([recv/3]).

-export_type([expiry_time/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Internal API
%%------------------------------------------------------------------------------------------------------------------------
-export([connect_and_delegate_owner/5]).

%%------------------------------------------------------------------------------------------------------------------------
%% Types
%%------------------------------------------------------------------------------------------------------------------------
-type expiry_time() :: erlang:timestamp() | infinity.

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec timeout_to_expiry_time(timeout()) -> expiry_time().
timeout_to_expiry_time(infinity) -> infinity;
timeout_to_expiry_time(Timeout)  ->
    {MegaSecs, Secs, MicroSecs} = now(),
    {MegaSecs, Secs, MicroSecs + Timeout * 1000}.

-spec connect(mqttc:address(), inet:port_number(), [gen_tcp:connect_option()], expiry_time()) ->
                     {ok, inet:socket()} | {error, inet:posix() | timeout}.
connect(Address, Port, Options, ExpiryTime) when is_binary(Address) ->
    connect(binary_to_list(Address), Port, Options, ExpiryTime);
connect(Address, Port, Options, ExpiryTime) ->
    Timeout = calc_timeout_from_expiry_time(ExpiryTime),
    apply_with_timeout(?MODULE, connect_and_delegate_owner, [self(), Address, Port, Options, Timeout], Timeout).

-spec send(inet:socket(), iodata(), expiry_time()) -> ok | {error, inet:posix() | timeout | closed}.
send(Socket, Data, ExpiryTime) ->
    Timeout = calc_timeout_from_expiry_time(ExpiryTime),
    apply_with_timeout(gen_tcp, send, [Socket, Data], Timeout).

-spec recv(inet:socket(), non_neg_integer(), expiry_time()) -> {ok, iodata()} | {error, inet:posix() | timeout | closed}.
recv(Socket, Size, ExpiryTime) ->
    Timeout = calc_timeout_from_expiry_time(ExpiryTime),
    apply_with_timeout(gen_tcp, recv, [Socket, Size, Timeout], Timeout).

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
-spec connect_and_delegate_owner(pid(), inet:ip_address()|inet:hostname(), inet:port_number(),
                                 [gen_tcp:connect_option()], timeout()) ->
                                        {ok, inet:socket()} | {error, inet:posix() | timeout}.
connect_and_delegate_owner(Owner, Address, Port, Options, Timeout) ->
    case gen_tcp:connect(Address, Port, Options, Timeout) of
        {error, Reason} -> {error, Reason};
        {ok, Socket}    ->
            case gen_tcp:controlling_process(Socket, Owner) of
                {error, Reason} -> {error, Reason};
                ok              -> {ok, Socket}
            end
    end.

-spec calc_timeout_from_expiry_time(expiry_time()) -> timeout().
calc_timeout_from_expiry_time(infinity)   -> infinity;
calc_timeout_from_expiry_time(ExpiryTime) ->
    TimeoutMicroSecs = max(0, timer:now_diff(ExpiryTime, now())),
    TimeoutMicroSecs div 1000.

-spec apply_with_timeout(module(), atom(), [term()], timeout()) -> term() | {error, timeout}.
apply_with_timeout(Module, Function, Args, Timeout) ->
    case rpc:call(node(), Module, Function, Args, Timeout) of
        {badrpc, timeout} -> {error, timeout};
        {badrpc, Reason}  -> error({badrpc, Reason}, [Module, Function, Args, Timeout]); % unexpected error
        OriginalResponse  -> OriginalResponse
    end.
