%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([connect/4]).
-export([publish/4]).
-export([subscribe/2]).
-export([unsubscribe/2]).
-export([close/1]).
-export([controlling_process/2]).
-export([setopts/2, getopts/2]).

-exprot_type([address/0]).
-export_type([connection/0]).
-export_type([connect_option/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Types
%%------------------------------------------------------------------------------------------------------------------------
-type address() :: inet:ip_address() | inet:hostname() | binary().
-type connection() :: term(). % TODO: pid()

-type connect_option() :: {clean_session, mqttm:flag()} % default: true
                        | {keep_alive_timer, mqttm:non_neg_seconds()} % defualt: 120
                        | {username, binary()}
                        | {password, binary()}
                        | {will, mqttm:will()}
                        | {timeout, timeout()}. % TODO: add tcp options

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec connect(address(), inet:port_number(), mqttm:client_id(), [connect_option()]) ->
                     {ok, connection()} | {error, Reason} when
      Reason :: inet:posix() | mqttm:connect_error_code() | term().
connect(Address, Port, ClientId, Options) ->
    mqttc_session_sup:start_child({self(), Address, Port, ClientId, Options}).
    %% case do_tcp_connect(Address, Port, Options) of
    %%     {error, Reason} -> {error, Reason};
    %%     {ok, Socket}    -> do_mqtt_connect(Socket, ClientId, Options)
    %% end.

%% -spec publish(connection(), mqttm:topic_name(), binary(), mqttm:qos_level()) -> ok | {error, Reason::term()}.
publish(Connection, TopicName, Payload, QosLevel) ->
    error(not_implemented, [Connection, TopicName, Payload, QosLevel]).

%%-spec subscribe(connection(), [{mqttm:topic_name(), mqttm:qos_level()}]) -> {ok, [mqttm:qos_level()]} | {error, Reason::term()}.
subscribe(Connection, TopicList) ->
    error(not_implemented, [Connection, TopicList]).

%%-spec unsubscribe(connection(), [mqttm:topic_name()]) -> ok | {error, Reason::term()}.
unsubscribe(Connection, TopicList) ->
    error(not_implemented, [Connection, TopicList]).

%%-spec close(connection()) -> ok | {error, Reason::term()}.
close(Connection) ->
    error(not_implemented, [Connection]).

controlling_process(Connection, Pid) ->
    error(not_implemented, [Connection, Pid]).

setopts(_, _) ->
    error(not_implemented).

getopts(_, _) ->
    error(not_implemented).

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
%% -spec do_tcp_connect(address(), inet:port_number(), [connect_option()]) -> {ok, inet:socket()} | {error, inet:posix()}.
%% do_tcp_connect(Address0, Port, Options) ->
%%     Address1 = case is_binary(Address0) of
%%                    true  -> binary_to_list(Address0);
%%                    false -> Address0
%%                end,
%%     gen_tcp:connect(Address1, Port, [{active, false}, binary], proplists:get_value(timeout, Options, infinity)).

%% -spec do_mqtt_connect(inet:socket(), mqttm:client_id(), [connect_option()]) -> {ok, connection()} | {error, Reason} when
%%       Reason :: inet:posix() | mqttm:connect_error_code() | term().
%% do_mqtt_connect(Socket, ClientId, Options) ->
%%     ConnectMessage = mqttm:make_connect(ClientId, Options),
%%     case gen_tcp:send(Socket, mqttm:encode(ConnectMessage)) of
%%         {error, Reason} -> {error, Reason};
%%         ok              ->
%%             case gen_tcp:recv(Socket, 4) of
%%                 {error, Reason} -> {error, Reason};
%%                 {ok, Bytes}     ->
%%                     {[ConnackMessage], <<"">>} = mqttm:decode(Bytes),
%%                     {ok, {Socket, ConnackMessage}}
%%             end
%%     end.
