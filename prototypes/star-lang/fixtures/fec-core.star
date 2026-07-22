(spec-library "org.starintel/fec@1"
  (:version "1.0.0"
   :digest "sha256:fec-core-v1-research-fixture")

  (import "org.starintel/core@1"
    :version "1.0.0"
    :digest "sha256:core-v1-research-fixture")

  (scalar candidate-id
    (:base string
     :pattern "^[HSP][A-Z0-9]{8}$"))

  (scalar committee-id
    (:base string
     :pattern "^C[0-9]{8}$"))

  (scalar file-number
    (:base integer
     :minimum 1))

  (scalar fec-money
    (:base decimal
     :scale 2))

  (scalar state-code
    (:base string
     :pattern "^[A-Z]{2}$"))

  (enum office
    (president senate house))

  (enum amendment-status
    (new amendment termination unknown))

  (enum support-oppose
    (support oppose unknown))

  (document entity
    (:persistence persistent)
    (fec-id string :optional)
    (name string :required)
    (street-1 string :optional)
    (street-2 string :optional)
    (city string :optional)
    (state state-code :optional)
    (zip-code string :optional)
    (employer string :optional)
    (occupation string :optional)
    (raw map :required))

  (document candidate
    (:extends entity
     :persistence persistent)
    (candidate-id candidate-id :required)
    (party-code string :optional)
    (party-name string :optional)
    (office office :required)
    (office-state state-code :optional)
    (office-district string :optional)
    (election-years (list integer) :required))

  (document committee
    (:extends entity
     :persistence persistent)
    (committee-id committee-id :required)
    (committee-type-code string :optional)
    (designation-code string :optional)
    (connected-organization-name string :optional)
    (treasurer-name string :optional)
    (candidate-ids (list candidate-id) :optional))

  (document filing
    (:persistence persistent)
    (file-number file-number :required)
    (committee-id committee-id :required)
    (form-type string :required)
    (report-type string :optional)
    (amendment-status amendment-status :required)
    (previous-file-number file-number :optional)
    (coverage-start-date iso-date :optional)
    (coverage-end-date iso-date :optional)
    (receipt-date iso-date :optional)
    (image-number string :optional)
    (most-recent boolean :required)
    (raw map :required))

  (document receipt
    (:persistence persistent)
    (committee-id committee-id :required)
    (contributor reference :required)
    (transaction-date iso-date :required)
    (amount fec-money :required)
    (aggregate-amount fec-money :optional)
    (file-number file-number :optional)
    (transaction-id string :optional)
    (sub-id string :optional)
    (amendment-status amendment-status :required)
    (memo-text string :optional)
    (raw map :required))

  (document disbursement
    (:persistence persistent)
    (committee-id committee-id :required)
    (payee reference :required)
    (transaction-date iso-date :required)
    (amount fec-money :required)
    (purpose string :optional)
    (file-number file-number :optional)
    (transaction-id string :optional)
    (sub-id string :optional)
    (amendment-status amendment-status :required)
    (raw map :required))

  (document independent-expenditure
    (:persistence persistent)
    (committee-id committee-id :required)
    (candidate-id candidate-id :required)
    (support-oppose support-oppose :required)
    (expenditure-date iso-date :required)
    (amount fec-money :required)
    (payee reference :optional)
    (purpose string :optional)
    (file-number file-number :optional)
    (transaction-id string :optional)
    (sub-id string :optional)
    (amendment-status amendment-status :required)
    (raw map :required))

  (predicate candidate-committee
    (:source candidate
     :destination committee))

  (predicate contributed-to
    (:source entity
     :destination committee))

  (predicate paid-to
    (:source committee
     :destination entity))

  (predicate independent-expenditure-about
    (:source committee
     :destination candidate))

  (predicate filed
    (:source committee
     :destination filing))

  (message ingest-page
    (:fields
     ((endpoint string :required)
      (cycle integer :optional)
      (page integer :required)
      (results (list map) :required)
      (retrieved-at iso-datetime :required))))

  (message resolve-amendments
    (:fields
     ((committee-id committee-id :required)
      (cycle integer :required)
      (records (list reference) :required))))

  (message index-fec-record
    (:fields
     ((document reference :required)
      (source-endpoint string :required)
      (cycle integer :optional)))))
