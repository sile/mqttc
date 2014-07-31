%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc header file for eunit

%%------------------------------------------------------------------------------------------------------------------------
%% Macros
%%------------------------------------------------------------------------------------------------------------------------
-define(assertDown(Monitor, Pid, ExpectedReason),
        (fun () ->
                 receive {'DOWN', Monitor, _, Pid, Reason} ->
                         ?assertMatch(ExpectedReason, Reason)
                 after 100 -> ?assert(timeout)
                 end
         end)()).

-define(assertDown(Pid, ExpectedReason),
        (fun (Monitor) ->
                 ?assertDown(Monitor, Pid, ExpectedReason)
         end)(monitor(process, Pid))).

-define(executeThenAssertDown(Exp, Pid, ExpectedReason),
        (fun (Monitor) ->
                 Exp,
                 ?assertDown(Monitor, Pid, ExpectedReason)
         end)(monitor(process, Pid))).

-define(assertReceive(ExpectedMessage),
        (fun () ->
                 receive
                     ExpectedMessage -> ?assert(true)
                 after 100 ->
                         receive
                             UnexpectedMessage -> ?assertMatch(ExpectedMessage, UnexpectedMessage)
                         after 0 -> ?assert(timeout)
                         end
                 end
         end)()).

-define(assertNotReceive(UnExpectedMessage),
        (fun () ->
                 receive
                     UnExpectedMessage = ReceivedMessage->
                         ?debugVal(ReceivedMessage),
                         ?assert(unexpected_message_received)
                 after 50 -> ?assert(true)
                 end
         end)()).


-define(assertAlive(Pid),
        (fun () ->
                 Monitor = monitor(process, Pid),
                 receive {'DOWN', Monitor, _, Pid, Reason} ->
                         ?debugVal(Pid),
                         ?debugVal(Reason),
                         ?assert(process_unexpectedly_down)
                 after 50 ->
                         _ = demonitor(Monitor, [flush]),
                         ?assert(true)
                 end
         end)()).
