(spec-library "example/local-loader@1"
  (:version "1.0.0")
  (import "org.starintel/core@1"
    :version "1.0.0"
    :digest "sha256:REPLACE_WITH_STARINTEL_CORE_SHA256"
    :path "starintel-core.star")
  (document example-record
    (:extends org.starintel/core@1/document
     :persistence persistent)
    (name string :required)))
