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
-export([publish/4]).

%% -export([subscribe/2]).
%% -export([unsubscribe/2]).
%% -export([setopts/2, getopts/2]).
%% -export([controlling_process/2]).
%% -export([which_connections/0]).

-export_type([address/0]).
-export_type([session/0, session_name/0, session_name_spec/0]).
-export_type([session_status/0]).
-export_type([connect_opt/0, connect_opts/0]).
-export_type([async_opt/0]).
-export_type([publish_opt/0, publish_opts/0]).
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

-type session_status() :: disconnected | connecting | connected.

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

-type tcp_error_reason() :: {tcp_error, connect, inet:posix() | timeout}
                          | {tcp_error, send,    inet:posix() | timeout | closed}
                          | {tcp_error, recv,    inet:posix() | timeout | closed}
                          | {tcp_error, setopts, inet:posix()}.

-type mqtt_error_reason() :: {mqtt_error, connect, {rejected, mqttm:connect_return_code()}}
                           | {mqtt_error, conncet, {unexpected_response, term()}}
                           | {mqtt_error, Command::atom(), disconnected | connecting | connected}.

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start(mqttm:client_id()) -> {ok, pid()} | {error, Reasion::term()}.
start(ClientId) ->
    mqttc_session_sup:start_child({undefined, self(), ClientId}).

-spec start(session_name_spec(), mqttm:client_id()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start(Name, ClientId) ->
    mqttc_session_sup:start_child({Name, self(), ClientId}).

-spec start_link(mqttm:client_id()) -> {ok, pid()} | {error, Reasion::term()}.
start_link(ClientId) ->
    mqttc_session_sup:start_child({undefined, {link, self()}, ClientId}).

-spec start_link(session_name_spec(), mqttm:client_id()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start_link(Name, ClientId) ->
    mqttc_session_sup:start_child({Name, {link, self()}, ClientId}).

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

%% -spec subscribe(connection(), [{mqttm:topic_name(), mqttm:qos_level()}]) -> {ok, [mqttm:qos_level()]} | {error, Reason::term()}.
%% subscribe(Connection, TopicList) ->
%%     Msg = mqttm:make_subscribe(false, 0, TopicList),
%%     mqttc_session:subscribe(Connection, Msg).

%% -spec unsubscribe(connection(), [mqttm:topic_name()]) -> ok | {error, Reason::term()}.
%% unsubscribe(Connection, TopicList) ->
%%     %% TODO: 既に受信している分をフラッシュする?
%%     Msg = mqttm:make_unsubscribe(false, 0, TopicList),
%%     mqttc_session:unsubscribe(Connection, Msg).

%% setopts(_, _) ->
%%     error(not_implemented).

%% getopts(_, _) ->
%%     error(not_implemented).

%% -spec which_connections() -> [connection()].
%% which_connections() ->
%%     mqttc_session_sup:which_children().


%% where({global, Name}) -> global:whereis_name(Name);
%% where({via, Module, Name}) -> Module:whereis_name(Name);
%% where({local, Name})  -> whereis(Name).

