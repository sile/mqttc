%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start/1, start/2]).
-export([start_link/1, start_link/2]).
-export([stop/1]).
-export([get_session_status/1]).
-export([get_client_id/1]).
-export([connect/4]).
-export([disconnect/1, disconnect/2]).
-export([ping/1]).
-export([publish/4]).
-export([subscribe/2, subscribe/3]).
-export([unsubscribe/2, unsubscribe/3]).
-export([which_sessions/0]).
%% -export([controlling_process/2]).

-export_type([address/0]).
-export_type([session/0, session_name/0, session_name_spec/0]).
-export_type([session_status/0]).
-export_type([connect_opt/0, connect_opts/0]).
-export_type([async_opt/0]).
-export_type([publish_opt/0, publish_opts/0]).
-exprot_type([subscribe_opt/0, subscribe_opts/0]).
-exprot_type([unsubscribe_opt/0, unsubscribe_opts/0]).
-export_type([tcp_error_reason/0]).
-export_type([mqtt_error_reason/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Types
%%------------------------------------------------------------------------------------------------------------------------
-type address() :: inet:ip_address() | inet:hostname() | binary().

-type session() :: pid() | session_name().
-type session_name():: (LocalName::atom())
                     | {LocalName::atom(), node()}
                     | {global, GlobalName::term()}
                     | {via, module(), ViaName::term()}.
-type session_name_spec() :: {local, LocalName::atom()}
                           | {global, GlobalName::term()}
                           | {via, module(), ViaName::term()}.

-type session_status() :: disconnecting | disconnected | connecting | connected.

-type connect_opts() :: [connect_opt()].
-type connect_opt() :: {clean_session, mqttm:flag()} % default: true
                     | {keep_alive_timer, mqttm:non_neg_seconds()} % defualt: 120
                     | {username, binary()}
                     | {password, binary()}
                     | {will, mqttm:will()}
                     | {timeout, timeout()} % default: 5000
                     | {tcp_connect_opts, [gen_tcp:connet_option()]}.

-type async_opt() :: {async, boolean()}
                   | {notify_tag, term()}.

-type publish_opts() :: [publish_opt()].
-type publish_opt() :: {qos, mqttm:qos_level()} % default: 0
                     | {retain, boolean()} % default: false
                     | {timeout, timeout()} % default: 5000
                     | async_opt().

-type subscribe_opts() :: [subscribe_opt()].
-type subscribe_opt() :: {timeout, timeout()}. % default: 5000

-type unsubscribe_opts() :: [unsubscribe_opt()].
-type unsubscribe_opt() :: {timeout, timeout()}. % default: 5000

-type tcp_error_reason() :: {tcp_error, connect, inet:posix() | timeout}
                          | {tcp_error, send,    inet:posix() | timeout | closed}
                          | {tcp_error, recv,    inet:posix() | timeout | closed}
                          | {tcp_error, setopts, inet:posix()}.

-type mqtt_error_reason() :: {mqtt_error, connect, {rejected, mqttm:connect_return_code()}}
                           | {mqtt_error, connect, canceled}
                           | {mqtt_error, connect, {disconnected, term()}}
                           | {mqtt_error, conncet, {unexpected_response, term()}}
                           | {mqtt_error, Command::atom(), session_status()}
                           | {mqtt_error, recv, {unexpected_message, mqttm:message()}}.

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start(mqttm:client_id()) -> {ok, pid()} | {error, Reasion::term()}.
start(ClientId) ->
    mqttc_session_sup:start_child({undefined, self(), ClientId}).

-spec start(session_name_spec(), mqttm:client_id()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start(Name, ClientId) ->
    mqttc_session_sup:start_child({Name, {undefined, self(), ClientId}}).

-spec start_link(mqttm:client_id()) -> {ok, pid()} | {error, Reasion::term()}.
start_link(ClientId) ->
    mqttc_session_sup:start_child({self(), self(), ClientId}).

-spec start_link(session_name_spec(), mqttm:client_id()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start_link(Name, ClientId) ->
    mqttc_session_sup:start_child({Name, {self(), self(), ClientId}}).

-spec stop(session()) -> ok.
stop(Session) ->
    mqttc_session:stop(Session).

-spec get_session_status(session()) -> session_status().
get_session_status(Session) ->
    mqttc_session:get_status(Session).

-spec get_client_id(session()) -> mqttm:client_id().
get_client_id(Session) ->
    mqttc_session:get_client_id(Session).

-spec connect(session(), address(), inet:port_number(), connect_opts()) -> ok | {error, Reason} when
      Reason :: tcp_error_reason() | mqtt_error_reason().
connect(Session, Address, Port, Options) ->
    mqttc_session:connect(Session, Address, Port, Options).

%% @equiv disconnect(Session, 5000)
-spec disconnect(session()) -> ok | {error, Reason} when
      Reason :: tcp_error_reason() | mqtt_error_reason().
disconnect(Session) ->
    disconnect(Session, 5000).

-spec disconnect(session(), timeout()) -> ok | {error, Reason} when
      Reason :: tcp_error_reason() | mqtt_error_reason().
disconnect(Session, Timeout) ->
    mqttc_session:disconnect(Session, Timeout).

-spec publish(session(), mqttm:topic_name(), binary(), publish_opts()) -> ok | {error, Reason} when
      Reason :: tcp_error_reason() | mqtt_error_reason().
publish(Session, TopicName, Payload, Options) ->
    mqttc_session:publish(Session, TopicName, Payload, Options).

-spec ping(session()) -> ok.
ping(Session) ->
    mqttc_session:ping(Session).

-spec subscribe(session(), [{mqttm:topic_name(), mqttm:qos_level()}]) ->
                       {ok, [mqttm:qos_level()]} | {error, Reason::term()}.
subscribe(Session, TopicList) ->
    subscribe(Session, TopicList, []).

-spec subscribe(session(), [{mqttm:topic_name(), mqttm:qos_level()}], subscribe_opts()) ->
                       {ok, [mqttm:qos_level()]} | {error, Reason::term()}.
subscribe(Session, TopicList, Options) ->
    mqttc_session:subscribe(Session, TopicList, Options).

-spec unsubscribe(session(), [mqttm:topic_name()]) -> ok | {error, Reason::term()}.
unsubscribe(Session, TopicList) ->
    unsubscribe(Session, TopicList, []).

-spec unsubscribe(session(), [mqttm:topic_name()], unsubscribe_opts()) -> ok | {error, Reason::term()}.
unsubscribe(Session, TopicList, Options) ->
    mqttc_session:unsubscribe(Session, TopicList, Options).

-spec which_sessions() -> [pid()].
which_sessions() ->
    mqttc_session_sup:which_children().
