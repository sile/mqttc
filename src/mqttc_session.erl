%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc supervisor for client MQTT session processes
%% @private
-module(mqttc_session).

-behaviour(gen_server).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/1]).

-export_type([start_arg/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(state,
        {
          controlling_process :: {pid(), reference()},
          socket :: inet:socket(),
          client_id :: mqttm:client_id()
        }).

-type start_arg() :: {ControllingProcess::pid(), mqttc:adddres(), inet:port_number(), mqttm:client_id(), [mqttc:connect_option()]}.

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start_link(start_arg()) -> {ok, pid()} | {error, Reason::term()}.
start_link(Arg) ->
    {_, _, _, _, Options} = Arg,
    Timeout = proplists:get_value(timeout, Options, infinity),
    case gen_server:start_link(?MODULE, Arg, [{timeout, Timeout}]) of
        {error, {shutdown, Reason}} -> {error, Reason};
        Other                       -> Other
    end.

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init({ControllingProcess, Address, Port, ClientId, Options}) ->
    Monitor = monitor(process, ControllingProcess),
    case mqttc_lib:connect(Address, Port, ClientId, Options) of
        {error, Reason} -> {stop, {shutdown, Reason}};
        {ok, Socket}    ->
            State =
                #state{
                   controlling_process = {ControllingProcess, Monitor},
                   socket = Socket,
                   client_id = ClientId
                  },
            {ok, State}
    end.

%% @private
handle_call(Request, From, State) ->
    {stop, {unknown_call, Request, From}, State}.

%% @private
handle_cast(Request, State) ->
    {stop, {unknown_cast, Request}, State}.

%% @private
handle_info({'DOWN', _, _, _, _}, State) ->
    %% TODO: gen_tcpの挙動に合わせる
    {stop, normal, State};
handle_info(Info, State) ->
    {stop, {unknown_info, Info}, State}.

%% @priavte
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
