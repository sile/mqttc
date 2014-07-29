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
        (fun () ->
                 Monitor = monitor(process, Pid),
                 ?assertDown(Monitor, Pid, ExpectedReason)
         end)()).

-define(assertAlive(Pid),
        (fun () ->
                 Monitor = monitor(process, Pid),
                 receive {'DOWN', Monitor, _, Pid, Reason} ->
                         ?debugVal(Pid),
                         ?debugVal(Reason),
                         ?assert(process_unexpectedly_down)
                 after 100 ->
                         _ = demonitor(Monitor, [flush]),
                         ?assert(true)
                 end
         end)()).
