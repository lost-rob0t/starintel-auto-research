(spec-library "org.starintel/bbp@1"
  (:version "1.0.0"
   :digest "sha256:bbp-domain-v1-research-fixture")

  (import "org.starintel/core@1"
    :version "1.0.0"
    :digest "sha256:core-v1-research-fixture")

  (scalar program-id
    (:base string
     :pattern "^[a-z0-9][a-z0-9._:-]{2,127}$"))

  (scalar run-id
    (:base string
     :pattern "^[a-z0-9][a-z0-9._:-]{2,127}$"))

  (scalar domain-name
    (:base string
     :pattern "^[A-Za-z0-9.-]+$"))

  (enum tool-name
    (subfinder httpx katana nmap))

  (enum tool-run-status
    (queued running completed failed cancelled))

  (document program
    (:persistence persistent)
    (program-id program-id :required)
    (name string :required)
    (scope (list string) :required)
    (raw map :required))

  (document target
    (:persistence persistent)
    (program-id program-id :required)
    (value string :required)
    (kind symbol :required)
    (in-scope boolean :required)
    (raw map :required))

  (document tool-run
    (:persistence persistent)
    (run-id run-id :required)
    (program-id program-id :required)
    (tool tool-name :required)
    (target string :required)
    (argv (list string) :required)
    (status tool-run-status :required)
    (exit-code integer :optional)
    (stdout string :optional)
    (stderr string :optional)
    (raw map :required))

  (document tool-observation
    (:persistence persistent)
    (run-id run-id :required)
    (program-id program-id :required)
    (tool tool-name :required)
    (target string :required)
    (value string :required)
    (raw map :required))

  (message register-program
    (:fields
     ((program-id program-id :required)
      (name string :required)
      (scope (list string) :required))))

  (message program-registered
    (:fields
     ((program-id program-id :required)
      (scope (list string) :required))))

  (message run-tool
    (:fields
     ((program-id program-id :required)
      (run-id run-id :required)
      (tool tool-name :required)
      (target string :required)
      (options map :optional))))

  (message tool-run-completed
    (:fields
     ((program-id program-id :required)
      (run-id run-id :required)
      (tool tool-name :required)
      (target string :required)
      (argv (list string) :required)
      (exit-code integer :required)
      (stdout string :required)
      (stderr string :required))))

  (message get-program-state
    (:fields
     ((program-id program-id :required))))

  (message program-state
    (:fields
     ((program-id program-id :required)
      (scope (list string) :required)
      (runs integer :required)))))
