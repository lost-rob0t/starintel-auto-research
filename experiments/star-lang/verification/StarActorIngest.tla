--------------------------- MODULE StarActorIngest ---------------------------
EXTENDS Naturals, TLC

CONSTANT RetryMax

VARIABLES phase,
          payloadClass,
          retry,
          genA,
          genB,
          persistence,
          outstandingAB,
          outstandingBA,
          poisonTerminal

vars == << phase, payloadClass, retry, genA, genB, persistence,
           outstandingAB, outstandingBA, poisonTerminal >>

Terminal == {"completed", "failed", "cancelled", "quarantined"}
NonTerminal == {"received", "a_running", "a_wait_b", "b_wait_a",
                "b_resume", "a_resume", "persist_ready", "retry_wait"}
Phases == Terminal \cup NonTerminal

Init ==
    /\ phase = "received"
    /\ payloadClass \in {"valid", "poison"}
    /\ retry = RetryMax
    /\ genA = 0
    /\ genB = 0
    /\ persistence \in {"up", "down"}
    /\ outstandingAB = FALSE
    /\ outstandingBA = FALSE
    /\ poisonTerminal = FALSE

RejectPoison ==
    /\ phase = "received"
    /\ payloadClass = "poison"
    /\ phase' = "quarantined"
    /\ poisonTerminal' = TRUE
    /\ outstandingAB' = FALSE
    /\ outstandingBA' = FALSE
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence >>

ValidateValid ==
    /\ phase = "received"
    /\ payloadClass = "valid"
    /\ phase' = "a_running"
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, outstandingBA, poisonTerminal >>

ASendB ==
    /\ phase = "a_running"
    /\ phase' = "a_wait_b"
    /\ outstandingAB' = TRUE
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingBA, poisonTerminal >>

BHandleAndAskA ==
    /\ phase = "a_wait_b"
    /\ outstandingAB
    /\ phase' = "b_wait_a"
    /\ outstandingBA' = TRUE
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, poisonTerminal >>

AHandleBA ==
    /\ phase = "b_wait_a"
    /\ outstandingBA
    /\ phase' = "b_resume"
    /\ outstandingBA' = FALSE
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, poisonTerminal >>

BResume ==
    /\ phase = "b_resume"
    /\ outstandingAB
    /\ phase' = "a_resume"
    /\ outstandingAB' = FALSE
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingBA, poisonTerminal >>

AResume ==
    /\ phase = "a_resume"
    /\ phase' = "persist_ready"
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, outstandingBA, poisonTerminal >>

PersistUp ==
    /\ phase = "persist_ready"
    /\ persistence = "up"
    /\ phase' = "completed"
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, outstandingBA, poisonTerminal >>

PersistDown ==
    /\ phase = "persist_ready"
    /\ persistence = "down"
    /\ retry > 0
    /\ phase' = "retry_wait"
    /\ retry' = retry - 1
    /\ UNCHANGED << payloadClass, genA, genB, persistence,
                    outstandingAB, outstandingBA, poisonTerminal >>

Retry ==
    /\ phase = "retry_wait"
    /\ phase' = "persist_ready"
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, outstandingBA, poisonTerminal >>

RetryExhausted ==
    /\ phase = "persist_ready"
    /\ persistence = "down"
    /\ retry = 0
    /\ phase' = "failed"
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    outstandingAB, outstandingBA, poisonTerminal >>

RecoverPersistence ==
    /\ phase \in {"persist_ready", "retry_wait"}
    /\ persistence = "down"
    /\ persistence' = "up"
    /\ UNCHANGED << phase, payloadClass, retry, genA, genB,
                    outstandingAB, outstandingBA, poisonTerminal >>

Cancel ==
    /\ phase \in NonTerminal \ {"received"}
    /\ phase' = "cancelled"
    /\ outstandingAB' = FALSE
    /\ outstandingBA' = FALSE
    /\ UNCHANGED << payloadClass, retry, genA, genB, persistence,
                    poisonTerminal >>

RestartA ==
    /\ phase \in {"a_wait_b", "b_wait_a", "b_resume", "a_resume"}
    /\ genA = 0
    /\ genA' = 1
    /\ phase' = "failed"
    /\ outstandingAB' = FALSE
    /\ outstandingBA' = FALSE
    /\ UNCHANGED << payloadClass, retry, genB, persistence, poisonTerminal >>

RestartB ==
    /\ phase \in {"a_wait_b", "b_wait_a", "b_resume"}
    /\ genB = 0
    /\ genB' = 1
    /\ phase' = "failed"
    /\ outstandingAB' = FALSE
    /\ outstandingBA' = FALSE
    /\ UNCHANGED << payloadClass, retry, genA, persistence, poisonTerminal >>

Next ==
    RejectPoison
    \/ ValidateValid
    \/ ASendB
    \/ BHandleAndAskA
    \/ AHandleBA
    \/ BResume
    \/ AResume
    \/ PersistUp
    \/ PersistDown
    \/ Retry
    \/ RetryExhausted
    \/ RecoverPersistence
    \/ Cancel
    \/ RestartA
    \/ RestartB

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

TypeOK ==
    /\ phase \in Phases
    /\ payloadClass \in {"valid", "poison"}
    /\ retry \in 0..RetryMax
    /\ genA \in 0..1
    /\ genB \in 0..1
    /\ persistence \in {"up", "down"}
    /\ outstandingAB \in BOOLEAN
    /\ outstandingBA \in BOOLEAN
    /\ poisonTerminal \in BOOLEAN

PoisonTerminalInvariant == poisonTerminal => phase = "quarantined"

TerminalClearsOutstanding ==
    (phase \in Terminal) => (~outstandingAB /\ ~outstandingBA)

PoisonCannotComplete == poisonTerminal => phase # "completed"

EventuallyTerminal == <> (phase \in Terminal)

=============================================================================
