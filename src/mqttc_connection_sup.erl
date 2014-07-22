%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc supervisor for client MQTT connection processes
%% @private
-module(mqttc_connection_sup).

-behaviour(supervisor).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/0]).
-export([start_child/1]).
-export([which_children/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @doc Starts supervisor process
-spec start_link() -> {ok, pid()} | {error, Reason::term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Starts child process
-spec start_child(mqttc_connection:start_arg()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start_child(Arg) ->
    supervisor:start_child(?MODULE, [Arg]).

-spec which_children() -> [pid()].
which_children() ->
    [Pid || {_, Pid, _, _} <- supervisor:which_children(?MODULE)].

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init([]) ->
    Connection = mqttc_connection,
    Children =
        [{Connection, {Connection, start_link, []}, temporary, 5000, worker, [Connection]}],
    {ok, { {simple_one_for_one, 5, 10}, Children} }.
