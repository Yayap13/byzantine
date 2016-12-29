% byzantine.erl: byzantine
%
% Short description: master/3(GeneralsNumber, TraitorsNumber, WhichAlgoToRun) spawns an general/0 process.
%
% Usage: byzantine:master(7,2,1).

-module(byzantine).
-export([master/3, general/0]). 

master(TotalOfGenerals, Traitors, AlgoToRun) ->
    random:seed(now()), % We have to use this deprecated "random" module because the TEDA env does not support the lastest iteration with "rand".
    Generals = TotalOfGenerals - Traitors,
    % Create the basic table containing all information needed for each General (Name, IsTraitor)
    BasicGeneralsInfo = generate_tuple_list(Generals, Traitors, []),
    %io:format("BasicGeneralsInfo: ~p~n", [BasicGeneralsInfo]),
    io:format("In master:: Master will spawn ~p loyal generals and ~p traitors..~n", [Generals, Traitors]),
    % Spawn each general and add his Pid to the GeneralsInfo
    GeneralsInfo = spawn_generals(BasicGeneralsInfo, []),
    io:format("In master:: Master has spawned the generals.~n"),

    % Each general will receive all the information needed to function properly (Other generals pids, etc..)
    send_master_to_all(GeneralsInfo, setInfo, GeneralsInfo),

    % Wait for all generals to be ready before starting our algo
    wait_general_ready(TotalOfGenerals),

    % Everything is now setup and ready, start algo now!
    io:format("In master:: Everything is ready and we should start the algo.~n"),
    
    % Choose which algo to run based on the params
    if
        AlgoToRun==1 ->
            send_master_to_all(GeneralsInfo, start_oral_message_algo, Traitors);
        AlgoToRun==2 ->
            send_master_to_all(GeneralsInfo, start_signed_message_algo, Traitors)
    end,

    % Each general will tell the master process when he has deduced an attack choice and finished his execution.
    wait_general_end(TotalOfGenerals-1).

general() ->
    receive
        % setInfo message is used to create a local list of all others generals(GeneralsInfo), and tell master that this process is ready to start.
        {setInfo, Data, MasterPid} ->
            %io:format("In general(~p):: setInfo received from process ~p~n", [self(), MasterPid]),
            GeneralsInfo = Data,
            random:seed(now()),
            AttackDecision = random:uniform(2)-1,
            MasterPid ! {ready, self()},
            IsTraitor = am_i_traitor(GeneralsInfo, -1),
            general(ready, GeneralsInfo, AttackDecision, IsTraitor, MasterPid)
    end.

general(ready, GeneralsInfo, AttackDecision, IsTraitor, MasterPid) ->
    receive
        % This message permit to setup and start the algo of Oral Messages for each general
        {start_oral_message_algo, Traitors, _} when Traitors>0 ->
            %io:format("In general(~p):: Start oral message received!~n", [self()]),
            %io:format("In general(~p):: GeneralsInfo: ~n~p~n", [self(), GeneralsInfo]),

            [FirstGeneral|RestGenerals] = GeneralsInfo,
            CommanderPid = get_pid_from_generalsinfo(FirstGeneral),
            if
                self()==CommanderPid ->
                    %io:format("In general(~p):: I am the commander!~n", [self()]),
                    print_vote_decision(AttackDecision, IsTraitor),
                    send_to_all_other_generals(GeneralsInfo, decision, AttackDecision, IsTraitor);
                self()/=CommanderPid ->
                    TotalRounds = Traitors+1,
                    general(oralMessage, RestGenerals, 1, TotalRounds, IsTraitor, [], MasterPid)
            end;

        % Just in case launching the algo is useless^^
        {start_oral_message_algo, Traitors, _} when Traitors=<0 ->
            io:format("In general(~p):: Pas de traitres == Pas de calculs!~n", [self()]);

        % This message is there to setup and start the algo of Signed messages for each general
        {start_signed_message_algo, _Traitors, _} ->
            %io:format("In general(~p):: Start message passing received!~n", [self()]),

            [FirstGeneral|RestGenerals] = GeneralsInfo,
            CommanderPid = get_pid_from_generalsinfo(FirstGeneral),
            if
                self()==CommanderPid ->
                    %io:format("In general(~p):: I am the commander!~n", [self()]),
                    print_vote_decision(AttackDecision, IsTraitor),
                    send_to_all_other_generals(RestGenerals, decisionSigned, {AttackDecision, []}, IsTraitor);
                self()/=CommanderPid ->
                    general(signedMessage, RestGenerals, [], 1, IsTraitor, MasterPid)
            end
            % Use that below, you can change params ;)
            %general(signedMessage, GeneralsInfo, -1, IsTraitor, MasterPid)
    end.



% ------------------------------------------------------------------------------
% Oral message functions
% ------------------------------------------------------------------------------
general(oralMessage, GeneralsInfo, 1, TotalRounds, IsTraitor, Tree, MasterPid) ->
    receive
        % Receive direct order from the commander
        {decision, CommanderAttackDecision, _MasterPid} ->
            %io:format("In general(~p):: Received order: ~p from Commander~n", [self(), CommanderAttackDecision]),
            % Forward it to all others generals
            send_to_all_generals(GeneralsInfo, decision, {CommanderAttackDecision, [MasterPid] ++ [self()]}, IsTraitor),
            % Switch this general to the part when rounds=2,3,4,...
            general(oralMessage, GeneralsInfo, 2, TotalRounds, IsTraitor, Tree ++ [{CommanderAttackDecision, [MasterPid]}], MasterPid)
    end;

general(oralMessage, GeneralsInfo, CurrentRound, TotalRounds, IsTraitor, Tree, MasterPid) ->
    %io:format("In general(~p):: Lieutenant here!~n", [self()]),
    %io:format("In general(~p):: CurrentRound: ~p, TotalRounds: ~p~n", [self(), CurrentRound, TotalRounds]),
    % We calculate dynamicly how many messages we are supposed to receive this round Exemple: [(N-1)*(N-2)*(N-3)...]
    MessagesToReceive = calculate_messages_to_receive(length(GeneralsInfo)+1, 1, CurrentRound, 1),
    %io:format("MessagesToReceive: ~p~n", [MessagesToReceive]),

    ReceiveList = receive_decision_message(MessagesToReceive, []),

    if
        % We can't make a decision yet, more rounds are needed!
        CurrentRound/=TotalRounds ->
            %io:format("In general(~p):: ReceiveList: ~n~p~n", [self(), ReceiveList]),
            % When all messages for this round are received, we loop through all of them
            lists:foreach(fun({AttackDecision, PidList}) ->
                AlreadyInList = already_contains_pid(PidList, false),
                if
                    AlreadyInList==false ->
                        %io:format("In general(~p):: Sending..~n", [self()]),
                        % If this particular message does not contains our pid, we forward it to the others generals
                        send_to_all_generals(GeneralsInfo, decision, {AttackDecision, PidList ++ [self()]}, IsTraitor);
                    AlreadyInList ->
                        %io:format("In general(~p):: Nope..~n", [self()]),
                        ok
                end
            end, ReceiveList),
            % Recursive call, more rounds are needed!
            general(oralMessage, GeneralsInfo, CurrentRound+1, TotalRounds, IsTraitor, Tree ++ [ReceiveList], MasterPid);
        % Algo has finished. We have enough data to deduce the general order from the data in the tree!
        CurrentRound==TotalRounds ->
            %io:format("In general(~p):: ReceiveList: ~n~p~n", [self(), ReceiveList]),
            FinalTree = Tree ++ [ReceiveList],
            %io:format("In general(~p):: Tree: ~n~n~p~n~n", [self(), FinalTree]),

            % Magic deduction is starting, first get the "leaves" of the "tree" (Not really a tree but something that is looking quite similar but easier to work with in our case!)
            LeavesList = get_leave_list(FinalTree),
            % Magic function, details are in there. ;)
            Winner = deduction_from_leaves(LeavesList),
            print_attack_decision(Winner, IsTraitor),
            % Tell the master that we have choosen an order and we are finished
            MasterPid ! {endMessage, self()}
            
            %io:format("END!~n")
    end.


send_to_all_generals(GeneralsInfo, decision, {AttackDecision, PidList}, IsTraitor) ->
    %io:format("Data: ~p~n", [{M, AttackDecision}]),
    %timer:sleep(1), % Mandatory on windaube (Windows) because otherwise strange error..
    lists:foreach(fun(Info) ->
        Pid = get_pid_from_generalsinfo(Info),
        NewAttackDecision = traitor(IsTraitor, AttackDecision),
        %io:format("NewAttackDecision: ~p~n", [{M, NewAttackDecision}]),
        %io:format("Pid: ~p envoi a ~p Data:~p~n", [self(), Pid, {NewAttackDecision, PidList}]),
        Pid ! {decision, {NewAttackDecision, PidList}}
    end, GeneralsInfo).

% Will accumulate every message in one list and sort it before returning it
receive_decision_message(0, AlreadyReceived) -> lists:keysort(2, AlreadyReceived);
receive_decision_message(NumberDecisionToReceive, AlreadyReceived) ->
    receive
        {decision, {AttackDecision, PidList}} ->
            Result = AlreadyReceived ++ [{AttackDecision, PidList}],
            %io:format("In general(~p):: Messages received: ~p, Left: ~p~n", [self(), length(AlreadyReceived), NumberDecisionToReceive-1]),
            receive_decision_message(NumberDecisionToReceive-1, Result)
    end.

% Send to every general in GeneralsInfo except us.
send_to_all_other_generals(GeneralsInfo, decision, AttackDecision, IsTraitor) ->
    %io:format("Data: ~p~n", [{M, AttackDecision}]),
    %timer:sleep(1), % Mandatory on windaube (Windows) because otherwise strange error..
    lists:foreach(fun(Info) ->
        Pid = get_pid_from_generalsinfo(Info),
        NewAttackDecision = traitor(IsTraitor, AttackDecision),
        %io:format("NewAttackDecision: ~p~n", [{M, NewAttackDecision}]),
        if
            Pid/=self() ->
                %io:format("Pid: ~p envoi a ~p Data:~p~n", [self(), Pid, {M, NewAttackDecision}]),
                Pid ! {decision, NewAttackDecision, self()};
            true ->
                false
        end
    end, GeneralsInfo);

% Send to every general in GeneralsInfo except us.
send_to_all_other_generals(GeneralsInfo, decisionSigned, AttackDecisionStruct, IsTraitor) ->
    %io:format("Data: ~p~n", [{M, AttackDecision}]),
    %timer:sleep(1), % Mandatory on windaube (Windows) because otherwise strange error..
    %AttackDecision = get_decision_from_signed_attack_decision(SignedAttackDecision),

    lists:foreach(fun(Info) ->
        Pid = get_pid_from_generalsinfo(Info),
        NewAttackDecisionStruct = generate_signed_attack_decision(AttackDecisionStruct, IsTraitor),
        %io:format("NewAttackDecision: ~p~n", [{M, NewAttackDecision}]),
        if
            Pid/=self() ->
                %io:format("Pid: ~p envoi a ~p Data:~p~n", [self(), Pid, NewAttackDecisionStruct]),
                Pid ! {decision, NewAttackDecisionStruct, self()};
            true ->
                false
        end
    end, GeneralsInfo).

% Send to every general in GeneralsInfo except us and the ones in the SignedList.
send_to_all_other_generals_except_signed_list(GeneralsInfo, SignedList, decisionSigned, AttackDecisionStruct, IsTraitor) ->
    %io:format("Data: ~p~n", [{M, AttackDecision}]),
    %timer:sleep(1), % Mandatory on windaube (Windows) because otherwise strange error..
    %AttackDecision = get_decision_from_signed_attack_decision(SignedAttackDecision),

    lists:foreach(fun(Info) ->
        Pid = get_pid_from_generalsinfo(Info),
        NewAttackDecisionStruct = generate_signed_attack_decision(AttackDecisionStruct, IsTraitor),
        %io:format("NewAttackDecision: ~p~n", [{M, NewAttackDecision}]),
        if
            Pid/=self() ->
                IsInList = lists:member(Pid, SignedList),
                if
                    IsInList ->
                        %io:format("Pid: ~p envoi a ~p Data:~p~n", [self(), Pid, NewAttackDecisionStruct]),
                        Pid ! {decision, NewAttackDecisionStruct, self()};
                    true ->
                        false
                end;
            true ->
                false
        end
    end, GeneralsInfo). 

% Can calculate how many messages are received in each step.
calculate_messages_to_receive(_N, RoundToAchieve, RoundToAchieve, Value) -> Value;
calculate_messages_to_receive(N, CurrentRound, RoundToAchieve, Value) -> % 7, 0, 2, 1
    calculate_messages_to_receive(N, CurrentRound+1, RoundToAchieve, (N-CurrentRound) * Value).

already_contains_pid([], Bool) -> Bool;
already_contains_pid([FirstPid|RestPid], _Bool) ->
    if
        self()==FirstPid ->
            true;
        self()/=FirstPid ->
            already_contains_pid(RestPid, false)
    end.

get_leave_list([HeadList|RestList]) ->
    if
        RestList==[] ->
            %lists:keysort(2, HeadList);
            HeadList;
        RestList/=[] ->
            get_leave_list(RestList) 
    end.

deduction_from_leaves(LeavesList) ->
    if 
        length(LeavesList)/=1 ->
            %io:format("In general(~p):: Leaves: ~n~n~p~n~n", [self(), LeavesList]),
            
            % Will "remove" last message sender and format the list in a mergeable way.
            ProcessedLeavesList = process_leaves(LeavesList, []),
            %io:format("In general(~p):: ProcessedLeavesList: ~n~n~p~n~n", [self(), ProcessedLeavesList]),

            % We can merge each value to an array of choices
            Merged = merge_results(ProcessedLeavesList),
            %io:format("In general(~p):: Merge: ~n~n~p~n~n", [self(), Merged]),
            
            % We can deduce the winner at this level
            Winner = deduce_action(Merged, []),
            %io:format("In general(~p):: Winner: ~n~n~p~n~n", [self(), Winner]),
            
            % We reform our special data format to recursivly loop through it!
            WinnerSwaped = swap_tuple(Winner, []),

            % Time to deduce leaves level - 1.
            deduction_from_leaves(WinnerSwaped);

        % When we only have one choice, just deduce the order 66
        length(LeavesList)==1 ->
            [{Order,_List}] = LeavesList,
            Order
    end.

process_leaves([], ProcessedList) -> ProcessedList;
process_leaves([{Decision, PidList}|Tail], ProcessedList) ->
    %process_leaves(Tail, ProcessedList ++ [{lists:nth(length(PidList)-1, PidList), Decision}]).
    process_leaves(Tail, ProcessedList ++ [{lists:droplast(PidList), Decision}]).

merge_results(List) ->
    Fun = fun(Key) -> {Key,proplists:get_all_values(Key,List)} end,
    lists:sort(lists:map(Fun,proplists:get_keys(List))).

deduce_action([], DeducedList) -> DeducedList;
deduce_action([{Pid, DecisionList}|Tail], DeducedList) ->
    Winner = get_most_recurrent(DecisionList, 0),
    deduce_action(Tail, DeducedList ++ [{Pid, Winner}]).
    %io:format("In general(~p):: Winner: ~p~n",[self(), Winner]).

get_most_recurrent([], Value) ->
    if
        Value>0 ->
            1;
        true ->
            0
    end;
get_most_recurrent([0|Tail], Value) -> get_most_recurrent(Tail, Value-1);
get_most_recurrent([1|Tail], Value) -> get_most_recurrent(Tail, Value+1).

swap_tuple([], NewList) -> NewList;
swap_tuple([{A,B}|Tail], NewList) -> swap_tuple(Tail, NewList ++ [{B,A}]).



% ------------------------------------------------------------------------------
% Signed Message functions
% ------------------------------------------------------------------------------
general(signedMessage, GeneralsInfo, OrdersList, CurrentRound, IsTraitor, MasterPid) ->
    if
      OrdersList==[] -> % First round, receive general only
            %Orders = receive_signed_decision_message(length(GeneralsInfo)-1, []),
            receive
                {decision, {AttackDecision, SignedList}, _SenderPid} ->
                    %io:format("In general(~p):: Received order: ~p from: ~p~n", [self(), {AttackDecision, SignedList}, SenderPid]),
                    send_to_all_other_generals(GeneralsInfo, decisionSigned, {AttackDecision, SignedList}, IsTraitor),
                    general(signedMessage, GeneralsInfo, [AttackDecision], CurrentRound+1, IsTraitor, MasterPid)
            end;

        OrdersList/=[] -> % All remainning rounds
            receive
                {decision, {AttackDecision, SignedList}, _SenderPid} ->
                    if
                        % That only the case when a Traitor has forged a message, just ignore it.
                        length(SignedList)<CurrentRound ->
                            general(signedMessage, GeneralsInfo, OrdersList, CurrentRound, IsTraitor, MasterPid);
                        
                        % When the message is not forged
                        true ->
                            %io:format("In general(~p):: Received order: ~p from: ~p~n", [self(), {AttackDecision, SignedList}, SenderPid]),
                            OrderAlreadyInList = lists:member(AttackDecision, OrdersList),
                            if
                                % We had it to the local OrderList and forward it to the others generals who haven't seen it yet.
                                % We also had our signature to it
                                OrderAlreadyInList==false ->
                                    send_to_all_other_generals_except_signed_list(GeneralsInfo, SignedList, decisionSigned, {AttackDecision, SignedList}, IsTraitor),
                                    general(signedMessage, GeneralsInfo, OrdersList ++ [AttackDecision], CurrentRound, IsTraitor, MasterPid);
                                % This case is when we already have that order in our local OrderList
                                true ->
                                    general(signedMessage, GeneralsInfo, OrdersList, CurrentRound, IsTraitor, MasterPid)
                            end

                        %length(SignedList)==1 ->
                        %    general(signedMessage, GeneralsInfo, OrdersList, CurrentRound, TotalRounds, IsTraitor, MasterPid)
                    end
            after
                % With this algo, we can't know for sure in advance how many messages are needed, so we just stop it when we stop receiving new messages.
                % One second is long enough in our case of machines in the same local network. (/!\ Maybe not enough in a real Internet environnement!)
                1000 ->
                    Winner = decision_from_order_list(OrdersList),
                    %io:format("OrdersList: ~p~n",[OrdersList]),
                    print_attack_decision(Winner, IsTraitor),
                    MasterPid ! {endMessage, self()}
            end
    end.


% Adds the decision with the signature to the current list, or can alter it if a traitor
generate_signed_attack_decision({AttackDecision, SignedList}, IsTraitor) -> 
    if
        IsTraitor == 0 ->
            %io:format("No Traitor!~n"),
            {AttackDecision, SignedList ++ [self()]};

        IsTraitor == 1 ->
            %io:format("Traitor!~n"),
            {traitor(AttackDecision, IsTraitor),[self()]}
    end.

decision_from_order_list([First|Second]) ->
    if
        Second==[] ->
            First;
        First==Second ->
            First;
        First/=Second ->
            0
    end.



% ------------------------------------------------------------------------------
% Master Helper functions
% ------------------------------------------------------------------------------
% Create basic list containing all generals and traitor info. This is used before spawing them.
generate_tuple_list(Generals, Traitors, List) ->
    Random = random:uniform(2),
    if
        Random==1 ->
            if
                Traitors>0 ->
                    generate_tuple_list(Generals, Traitors-1, [{list_to_atom("pid" ++ integer_to_list(Generals+Traitors)),1}] ++ List);

                Generals>0 ->
                    generate_tuple_list(Generals-1, Traitors, [{list_to_atom("pid" ++ integer_to_list(Generals+Traitors)),0}] ++ List);

                true ->
                    List
            end;
        Random==2 ->
            if
                Generals>0 ->
                    generate_tuple_list(Generals-1, Traitors, [{list_to_atom("pid" ++ integer_to_list(Generals+Traitors)),0}] ++ List);
                
                Traitors>0 ->
                    generate_tuple_list(Generals, Traitors-1, [{list_to_atom("pid" ++ integer_to_list(Generals+Traitors)),1}] ++ List);

                true ->
                    List
            end
    end.

% Add pid to tuple of {name, isTraitor} to {name, Pid, isTraitor}
add_pid(X, {A, B}) -> {A, X, B}.

% Spawn all generals list
spawn_generals([], AfterSpawnList) -> AfterSpawnList;
spawn_generals([Head|Tail], AfterSpawnList) ->
    Pid_general = spawn(?MODULE, general, []),
    spawn_generals(Tail, AfterSpawnList ++ [add_pid(Pid_general, Head)]).

% Get the Pid from tuple {name, Pid, isTraitor}
get_pid_from_generalsinfo({_,Pid,_}) -> Pid.

% Send Data to all generals in GeneralsInfo
send_master_to_all([], _, _) -> true;
send_master_to_all(GeneralsInfo, Atom, Data) ->
    lists:foreach(fun(Info) ->
        send_master_to_pid(get_pid_from_generalsinfo(Info), Atom, Data)
    end, GeneralsInfo).

% Send Data to a specific Pid
send_master_to_pid(Pid, Atom, Data) ->
    Pid ! {Atom, Data, self()}.

% Wait for every general to be ready
%wait_general_ready(GeneralsInfo) -> [ receive {ready, Pid} -> {io:format("In master:: all generals are ready!")} end  ||   Info <- GeneralsInfo, Pid = get_pid_from_generalsinfo(Info) ].
wait_general_ready(0) -> io:format("In master:: all generals are ready!~n");
wait_general_ready(LeftToWait) ->
    receive
        {ready, _Pid} ->
            %io:format("In master:: General ~p is ready.~n", [Pid]),
            wait_general_ready(LeftToWait-1)     
    end.

% Wait for every general to finish their algo
wait_general_end(0) -> io:format("In master:: algo has finished!~n");
wait_general_end(LeftToWait) ->
    receive
        {endMessage, _Pid} ->
            %io:format("In master:: General ~p has finished.~n", [Pid]),
            wait_general_end(LeftToWait-1)     
    end.

% Send garbage/random decision if we are a traitor messenger
traitor(IsTraitor, AttackDecision) ->
    if
        IsTraitor==1 ->
            %io:format("In general(~p):: I am the traitor!~n", [self()]),
            random:uniform(2)-1;
        IsTraitor==0 ->
            %io:format("AttackDecision: ~p~n", [AttackDecision]),
            AttackDecision
    end.

% To check if we are a traitor based on the GeneralsInfo
am_i_traitor([], Bool) -> Bool;
am_i_traitor([{_Name, Pid, Traitor}|Tail], _Bool) ->
    if
        Pid==self() ->
            am_i_traitor([], Traitor);
        true ->
            am_i_traitor(Tail, Traitor)
    end.

% Print our decision (choice is totally personnal)
print_vote_decision(0, 0) -> io:format("In general(~p):: Order to Retreat ~n", [self()]);
print_vote_decision(0, 1) -> io:format("In general(~p):: Order to Retreat <- Traitor!~n", [self()]);
print_vote_decision(1, 0) -> io:format("In general(~p):: Order to Attack ~n", [self()]);
print_vote_decision(1, 1) -> io:format("In general(~p):: Order to Attack <- Traitor!~n", [self()]).

% Print our decision after executing the algo
print_attack_decision(0, 0) -> io:format("In general(~p):: Decided to Retreat ~n", [self()]);
print_attack_decision(0, 1) -> io:format("In general(~p):: Decided to Retreat <- Traitor!~n", [self()]);
print_attack_decision(1, 0) -> io:format("In general(~p):: Decided to Attack ~n", [self()]);
print_attack_decision(1, 1) -> io:format("In general(~p):: Decided to Attack <- Traitor!~n", [self()]).





% A Wild Santa to make you smilie :D
% WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
% WW         ___ __     ____      ___    ___   _   _          WW
% WW        |   V  \   / _  )    / __|  / __| | | | |         WW
% WW        | /\ /\ | ( (/ /_   | /    | /    \ \_| |         WW
% WW        |_||_||_|  \_____|  |_|    |_|     \__  |         WW
% WW                                              | |         WW
% WW                          _.-"""-.          _/ /          WW
% WW                        _/_______ `.       |__/           WW
% WW                       / _______ \  \                     WW
% WW                       \/,-. ,-.\/   \                    WW
% WW                       ()>=   =<()`._ \_                  WW
% WW                     ,-(.--(_)--.)`-.`(_)                 WW
% WW                   ,'  /.-'\_/`-.\   `.                   WW
% WW                  /   /    `-'    \    \                  WW
% WW                ,'    \           /     `.                WW
% WW               /     _ `.       ,'  _     \               WW
% WW              /     _/   `-._.-'    \_     \              WW
% WW             /_______|     -|O      |_______\             WW
% WW            {________}______|_______{________}            WW
% WW            ,'   _ \(_____[|_=]______)  / _   `.          WW
% WW           /    / `'--------------------`' \    \         WW
% WW           `---'  |_____________________|   `---'         WW
% WW                    |_____|_____|_____|                   WW
% WW                    |__|_____|_____|__|                   WW
% WW        _           |_____|_____|_____|                   WW
% WW       | |           _                                    WW
% WW       | |          (_)        _                          WW
% WW  ___  | |__    ___  _   ___  | |_  ___  _    ____   ___  WW
% WW /  _| |  _ \  / __|| | / __| |  _||   V  \  / _  | / __| WW
% WW(  (_  | | \ || /   | | \__ \ | |  | /\ /\ |( (_| | \__ \ WW
% WW \___| |_| |_||_|   |_| |___/ |_|  |_||_||_| \____| |___/ WW
% WW                                                          WW
% WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW
