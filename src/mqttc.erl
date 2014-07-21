%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([connect/4]).
-export([publish/5]).
-export([subscribe/2]).
-export([unsubscribe/2]).
-export([close/1]).
-export([setopts/2, getopts/2]).
%%-export([controlling_process/2]).
-export([which_connections/0]).

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

-spec close(connection()) -> ok.
close(Connection) when is_pid(Connection) ->
    mqttc_session:close(Connection);
close(Connection) ->
    error(badarg, [Connection]).

%% TODO: queueが空になったことを通知してもらう仕組みをつける({active, N}に近い形で設定可能とする)
-spec publish(connection(), mqttm:topic_name(), binary(), mqttm:qos_level(), boolean()) -> ok.
publish(Connection, TopicName, Payload, QosLevel, RetainFlag) ->
    PublishMsg =
        case QosLevel of
            0 -> mqttm:make_publish(TopicName, Payload, RetainFlag);
            _ -> mqttm:make_publish(TopicName, Payload, RetainFlag, QosLevel, false, 0)
        end,
    mqttc_session:publish(Connection, PublishMsg).

%%-spec subscribe(connection(), [{mqttm:topic_name(), mqttm:qos_level()}]) -> {ok, [mqttm:qos_level()]} | {error, Reason::term()}.
subscribe(Connection, TopicList) ->
    error(not_implemented, [Connection, TopicList]).

%%-spec unsubscribe(connection(), [mqttm:topic_name()]) -> ok | {error, Reason::term()}.
unsubscribe(Connection, TopicList) ->
    error(not_implemented, [Connection, TopicList]).

setopts(_, _) ->
    error(not_implemented).

getopts(_, _) ->
    error(not_implemented).

-spec which_connections() -> [connection()].
which_connections() ->
    mqttc_session_sup:which_children().

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
