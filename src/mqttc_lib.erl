%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc_lib).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([connect/4]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec connect(mqttc:address(), inet:port_number(), mqttm:client_id(), [mqttc:connect_option()]) ->
                     {ok, mqttc:connection()} | {error, Reason} when
      Reason :: inet:posix() | mqttm:connect_error_code() | term().
connect(Address, Port, ClientId, Options) ->
    error(not_implemented, [Address, Port, ClientId, Options]).
