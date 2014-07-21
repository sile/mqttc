%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc_lib).

-include_lib("mqttm/include/mqttm.hrl").

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([connect/3, connect/4]).
-export([disconnect/1]).
-export([publish/2]).
-export([pubrel/2]).

%%------------------------------------------------------------------------------------------------------------------------
%% Macros
%%------------------------------------------------------------------------------------------------------------------------
-define(CONNACK_LENGTH, 4).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec connect(inet:socket(), mqttm:client_id(), [mqttc:connect_option()]) -> ok | {error, Reason} when
      Reason :: inet:posix() | mqttm:connect_error_code() | term().
connect(Socket, ClientId, Options) ->
    ConnectMsg = mqttm:make_connect(ClientId, Options),
    case gen_tcp:send(Socket, mqttm:encode(ConnectMsg)) of
        {error, Reason} -> {error, Reason};
        ok              ->
            case gen_tcp:recv(Socket, ?CONNACK_LENGTH) of
                {error, Reason} -> {error, Reason};
                {ok, Bytes}     ->
                    {[ConnackMsg], <<>>} = mqttm:decode(Bytes),
                    case ConnackMsg#mqttm_connack.return_code of
                        0    -> ok;
                        Code -> {error, {mqtt_connect_error, Code}}
                    end
            end
    end.

-spec connect(mqttc:address(), inet:port_number(), mqttm:client_id(), [mqttc:connect_option()]) ->
              {ok, mqttc:connection()} | {error, Reason} when
      Reason :: inet:posix() | mqttm:connect_error_code() | term().
connect(Address0, Port, ClientId, Options) ->
    Address1 = case is_binary(Address0) of
                   true  -> binary_to_list(Address0);
                   false -> Address0
               end,
    Timeout = proplists:get_value(timeout, Options, infinity),
    case gen_tcp:connect(Address1, Port, [{active, false}, binary], Timeout) of
        {error, Reason} -> {error, Reason};
        {ok, Socket}    ->
            case connect(Socket, ClientId, Options) of
                {error, Reason} -> {error, Reason};
                ok              -> {ok, Socket}
            end
    end.

-spec disconnect(inet:socket()) -> ok | {error, inet:posix()}.
disconnect(Socket) ->
    DisconnectMsg = mqttm:make_disconnect(),
    gen_tcp:send(Socket, mqttm:encode(DisconnectMsg)).

-spec publish(inet:socket(), mqttm:publish_message()) -> ok | {error, inet:posix()}.
publish(Socket, PublishMsg) ->
    gen_tcp:send(Socket, mqttm:encode(PublishMsg)).

-spec pubrel(inet:socket(), mqttm:message_id()) -> ok | {error, inet:posix()}.
pubrel(Socket, MessageId) ->
    Msg = mqttm:make_pubrel(false, MessageId),
    gen_tcp:send(Socket, mqttm:encode(Msg)).
