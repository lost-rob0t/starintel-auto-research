(analysis email-enumeration
  (:version 1)
  (:effects (:actor :agent :persist))
  (sequence
    (from target)
    (filter enumeration-target-p)
    (flat-map generate-email-candidates)
    (parallel 4 (through email-testing-actor))
    (filter found-candidate-p)
    (through review-agent)
    (checkpoint final-review-ready)
    (into persist)))
