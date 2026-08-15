(set-logic QF_LIA)
(declare-const birthYear Int)
(declare-const observationYear Int)
(declare-const age Int)
(declare-const minor Bool)

(assert (= age (- observationYear birthYear)))
(assert (>= age 0))
(assert (<= age 130))
(assert (=> minor (<= age 17)))
(assert (=> (not minor) (>= age 18)))

(assert (= birthYear 2000))
(assert (= observationYear 2026))
(assert minor)

(check-sat)
