(spec-library "org.starintel/core@1"
  (:version "1.0.0")

  (scalar document-id
    (:base string
     :pattern "^[A-Za-z0-9._~:/+-]{1,512}$"))

  (scalar unix-time
    (:base integer
     :minimum 0))

  (scalar confidence-score
    (:base decimal
     :minimum 0
     :maximum 1
     :scale 4))

  (scalar latitude
    (:base decimal
     :minimum -90
     :maximum 90
     :scale 8))

  (scalar longitude
    (:base decimal
     :minimum -180
     :maximum 180
     :scale 8))

  (scalar port-number
    (:base integer
     :minimum 0
     :maximum 65535))

  (scalar asn-number
    (:base integer
     :minimum 0
     :maximum 4294967295))

  (scalar uri
    (:base string
     :format uri))

  (scalar email-address
    (:base string
     :pattern "^[^[:space:]@]+@[^[:space:]@]+$"))

  (scalar phone-number
    (:base string
     :pattern "^\\+?[0-9(). -]{3,32}$"))

  (enum sensitivity
    (public internal confidential restricted secret unknown))

  (enum visibility
    (public private shared inherited unknown))

  (enum collection-status
    (raw normalized enriched verified disputed stale deleted unknown))

  (enum source-kind
    (api web file database message human sensor inference import export unknown))

  (enum hash-algorithm
    (sha256 sha512 blake2b blake3 md5 unknown))

  (enum relation-direction
    (directed symmetric inverse unknown))

  (enum target-state
    (pending scheduled running completed failed cancelled paused unknown))

  (document document
    (:persistence persistent)
    (id document-id :required)
    (rev string :optional)
    (dataset string :required)
    (dtype string :required)
    (schema-version string :required)
    (external-ids map :optional)
    (aliases (list string) :optional)
    (sources (list reference) :optional)
    (source-urls (list uri) :optional)
    (source-record-ids (list string) :optional)
    (source-kinds (list source-kind) :optional)
    (source-license string :optional)
    (source-terms uri :optional)
    (source-retrieved-at unix-time :optional)
    (collected-at unix-time :optional)
    (observed-at unix-time :optional)
    (first-seen-at unix-time :optional)
    (last-seen-at unix-time :optional)
    (created-at unix-time :optional)
    (updated-at unix-time :optional)
    (valid-from unix-time :optional)
    (valid-until unix-time :optional)
    (expires-at unix-time :optional)
    (collector string :optional)
    (collector-version string :optional)
    (collection-method string :optional)
    (collection-status collection-status :optional)
    (run-id string :optional)
    (correlation-id string :optional)
    (causation-id string :optional)
    (parent-id document-id :optional)
    (root-id document-id :optional)
    (confidence confidence-score :optional)
    (confidence-basis string :optional)
    (quality-score confidence-score :optional)
    (completeness-score confidence-score :optional)
    (verification-status string :optional)
    (verified-at unix-time :optional)
    (verified-by string :optional)
    (provenance map :optional)
    (chain-of-custody (list map) :optional)
    (transform-history (list map) :optional)
    (labels (list string) :optional)
    (tags (list string) :optional)
    (topics (list string) :optional)
    (language string :optional)
    (jurisdiction string :optional)
    (country-code string :optional)
    (region-code string :optional)
    (timezone string :optional)
    (sensitivity sensitivity :optional)
    (visibility visibility :optional)
    (owner string :optional)
    (access-control map :optional)
    (legal-basis string :optional)
    (retention-policy string :optional)
    (content-type string :optional)
    (encoding string :optional)
    (size-bytes integer :optional)
    (content-hash string :optional)
    (hash-algorithm hash-algorithm :optional)
    (normalized-hash string :optional)
    (raw map :optional)
    (raw-content string :optional)
    (notes string :optional)
    (deleted boolean :optional)
    (tombstone-reason string :optional)
    (extensions map :optional))

  (document person
    (:extends document
     :persistence persistent)
    (fname string :optional)
    (mname string :optional)
    (lname string :optional)
    (full-name string :optional)
    (display-name string :optional)
    (prefix string :optional)
    (suffix string :optional)
    (pronouns string :optional)
    (bio string :optional)
    (dob iso-date :optional)
    (date-of-death iso-date :optional)
    (age integer :optional)
    (gender string :optional)
    (nationality (list string) :optional)
    (citizenship (list string) :optional)
    (occupation (list string) :optional)
    (employer (list reference) :optional)
    (education (list map) :optional)
    (skills (list string) :optional)
    (interests (list string) :optional)
    (region string :optional)
    (addresses (list reference) :optional)
    (emails (list reference) :optional)
    (phones (list reference) :optional)
    (accounts (list reference) :optional)
    (images (list reference) :optional)
    (misc (list map) :optional)
    (etype string :optional)
    (eid string :optional))

  (document org
    (:extends document
     :persistence persistent)
    (reg string :optional)
    (registration-numbers map :optional)
    (name string :required)
    (legal-name string :optional)
    (alternate-names (list string) :optional)
    (bio string :optional)
    (description string :optional)
    (organization-type string :optional)
    (industry (list string) :optional)
    (founded-date iso-date :optional)
    (dissolved-date iso-date :optional)
    (status string :optional)
    (country string :optional)
    (jurisdictions (list string) :optional)
    (headquarters reference :optional)
    (addresses (list reference) :optional)
    (website uri :optional)
    (domains (list reference) :optional)
    (emails (list reference) :optional)
    (phones (list reference) :optional)
    (parent-org reference :optional)
    (subsidiaries (list reference) :optional)
    (officers (list reference) :optional)
    (employees (list reference) :optional)
    (owners (list reference) :optional)
    (beneficial-owners (list reference) :optional)
    (identifiers map :optional)
    (etype string :optional)
    (eid string :optional))

  (document relation
    (:extends document
     :persistence persistent)
    (source reference :required)
    (target reference :required)
    (predicate string :required)
    (direction relation-direction :optional)
    (inverse-predicate string :optional)
    (note string :optional)
    (evidence (list reference) :optional)
    (weight decimal :optional)
    (valid-at unix-time :optional)
    (ended-at unix-time :optional))

  (document domain
    (:extends document
     :persistence persistent)
    (name string :required)
    (unicode-name string :optional)
    (punycode-name string :optional)
    (record-type string :optional)
    (record string :optional)
    (resolved-addresses (list reference) :optional)
    (dns-records (list map) :optional)
    (nameservers (list string) :optional)
    (mx-records (list map) :optional)
    (txt-records (list string) :optional)
    (registrar string :optional)
    (registrant reference :optional)
    (whois map :optional)
    (registered-at unix-time :optional)
    (renewed-at unix-time :optional)
    (registry-expires-at unix-time :optional)
    (dnssec boolean :optional)
    (status-codes (list string) :optional))

  (document service
    (:extends document
     :persistence persistent)
    (host reference :required)
    (port port-number :required)
    (transport string :optional)
    (name string :optional)
    (product string :optional)
    (vendor string :optional)
    (version string :optional)
    (protocol string :optional)
    (scheme string :optional)
    (banner string :optional)
    (state string :optional)
    (tls boolean :optional)
    (tls-certificate reference :optional)
    (cpe (list string) :optional)
    (fingerprints map :optional)
    (first-open-at unix-time :optional)
    (last-open-at unix-time :optional))

  (document port
    (:extends document
     :persistence persistent)
    (number port-number :required)
    (transport string :optional)
    (protocol string :optional)
    (service reference :optional)
    (state string :optional)
    (reason string :optional)
    (banner string :optional)
    (host reference :optional)
    (first-open-at unix-time :optional)
    (last-open-at unix-time :optional))

  (document network
    (:extends document
     :persistence persistent)
    (org reference :optional)
    (subnet string :required)
    (asn asn-number :optional)
    (asn-name string :optional)
    (rir string :optional)
    (country string :optional)
    (netname string :optional)
    (description string :optional)
    (announced-prefixes (list string) :optional)
    (upstreams (list asn-number) :optional)
    (peers (list asn-number) :optional))

  (document asn
    (:extends document
     :persistence persistent)
    (number asn-number :required)
    (name string :optional)
    (org reference :optional)
    (country string :optional)
    (rir string :optional)
    (registry string :optional)
    (prefixes (list string) :optional)
    (upstreams (list asn-number) :optional)
    (peers (list asn-number) :optional))

  (document host
    (:extends document
     :persistence persistent)
    (hostname string :optional)
    (hostnames (list string) :optional)
    (ip string :required)
    (ip-version integer :optional)
    (mac string :optional)
    (os string :optional)
    (os-version string :optional)
    (device-type string :optional)
    (vendor string :optional)
    (network reference :optional)
    (asn asn-number :optional)
    (geo reference :optional)
    (ports (list reference) :optional)
    (services (list reference) :optional)
    (domains (list reference) :optional)
    (certificates (list reference) :optional)
    (cloud map :optional)
    (virtualization string :optional)
    (alive boolean :optional)
    (last-probed-at unix-time :optional))

  (document url
    (:extends document
     :persistence persistent)
    (url uri :required)
    (scheme string :optional)
    (username string :optional)
    (host string :optional)
    (port port-number :optional)
    (path string :optional)
    (query string :optional)
    (fragment string :optional)
    (canonical-url uri :optional)
    (final-url uri :optional)
    (status-code integer :optional)
    (method string :optional)
    (request-headers map :optional)
    (response-headers map :optional)
    (content string :optional)
    (content-title string :optional)
    (content-length integer :optional)
    (technologies (list string) :optional)
    (redirect-chain (list uri) :optional)
    (screenshot reference :optional)
    (fetched-at unix-time :optional))

  (document breach
    (:extends document
     :persistence persistent)
    (name string :optional)
    (total integer :optional)
    (description string :optional)
    (url uri :optional)
    (breached-at unix-time :optional)
    (published-at unix-time :optional)
    (data-classes (list string) :optional)
    (affected-organizations (list reference) :optional)
    (affected-identifiers (list string) :optional)
    (verified boolean :optional)
    (sensitive boolean :optional))

  (document email
    (:extends document
     :persistence persistent)
    (address email-address :required)
    (user string :optional)
    (domain string :optional)
    (display-name string :optional)
    (password string :optional)
    (password-hash string :optional)
    (hash-type string :optional)
    (breaches (list reference) :optional)
    (deliverable boolean :optional)
    (disposable boolean :optional)
    (role-account boolean :optional)
    (catch-all boolean :optional)
    (mx-valid boolean :optional)
    (provider string :optional)
    (last-verified-at unix-time :optional))

  (document email-message
    (:extends document
     :persistence persistent)
    (message-id string :optional)
    (thread-id string :optional)
    (subject string :optional)
    (body string :optional)
    (body-html string :optional)
    (to (list email-address) :optional)
    (from email-address :optional)
    (reply-to email-address :optional)
    (cc (list email-address) :optional)
    (bcc (list email-address) :optional)
    (headers map :optional)
    (attachments (list reference) :optional)
    (sent-at unix-time :optional)
    (received-at unix-time :optional)
    (in-reply-to string :optional)
    (references (list string) :optional)
    (mailbox string :optional)
    (flags (list string) :optional))

  (document user
    (:extends document
     :persistence persistent)
    (url uri :optional)
    (username string :required)
    (display-name string :optional)
    (name string :optional)
    (platform string :required)
    (platform-user-id string :optional)
    (bio string :optional)
    (avatar reference :optional)
    (banner reference :optional)
    (created-on-platform-at unix-time :optional)
    (followers-count integer :optional)
    (following-count integer :optional)
    (post-count integer :optional)
    (verified boolean :optional)
    (private boolean :optional)
    (suspended boolean :optional)
    (location string :optional)
    (website uri :optional)
    (emails (list reference) :optional)
    (phones (list reference) :optional)
    (misc (list map) :optional))

  (document phone
    (:extends document
     :persistence persistent)
    (number phone-number :required)
    (e164 string :optional)
    (national-number string :optional)
    (extension string :optional)
    (carrier string :optional)
    (status string :optional)
    (phone-type string :optional)
    (line-type string :optional)
    (valid boolean :optional)
    (reachable boolean :optional)
    (ported boolean :optional)
    (location string :optional)
    (last-verified-at unix-time :optional))

  (document geo
    (:extends document
     :persistence persistent)
    (lat latitude :required)
    (long longitude :required)
    (alt decimal :optional)
    (accuracy-meters decimal :optional)
    (geohash string :optional)
    (coordinate-system string :optional)
    (place-name string :optional)
    (place-kind string :optional))

  (document address
    (:extends geo
     :persistence persistent)
    (formatted string :optional)
    (street string :optional)
    (street2 string :optional)
    (unit string :optional)
    (city string :optional)
    (county string :optional)
    (state string :optional)
    (postal string :optional)
    (country string :optional)
    (address-type string :optional)
    (po-box string :optional)
    (building string :optional)
    (floor string :optional)
    (delivery-point string :optional)
    (validated boolean :optional)
    (validation-provider string :optional))

  (document message
    (:extends document
     :persistence persistent)
    (message string :required)
    (platform string :required)
    (user reference :optional)
    (is-reply boolean :optional)
    (media (list reference) :optional)
    (message-id string :optional)
    (reply-to reference :optional)
    (thread-id string :optional)
    (group string :optional)
    (channel string :optional)
    (mentions (list reference) :optional)
    (reactions map :optional)
    (edited boolean :optional)
    (edited-at unix-time :optional)
    (sent-at unix-time :optional)
    (deleted-at unix-time :optional))

  (document socialmpost
    (:extends document
     :persistence persistent)
    (content string :required)
    (user reference :optional)
    (platform string :optional)
    (platform-post-id string :optional)
    (replies (list reference) :optional)
    (media (list reference) :optional)
    (reply-count integer :optional)
    (repost-count integer :optional)
    (like-count integer :optional)
    (view-count integer :optional)
    (quote-count integer :optional)
    (bookmark-count integer :optional)
    (url uri :optional)
    (links (list uri) :optional)
    (hashtags (list string) :optional)
    (mentions (list reference) :optional)
    (title string :optional)
    (group string :optional)
    (reply-to reference :optional)
    (conversation-id string :optional)
    (published-at unix-time :optional)
    (edited-at unix-time :optional)
    (sensitive boolean :optional))

  (document target
    (:extends document
     :persistence persistent)
    (actor string :required)
    (target string :required)
    (target-type string :optional)
    (scope reference :optional)
    (delay integer :optional)
    (recurring boolean :optional)
    (schedule string :optional)
    (options map :optional)
    (state target-state :optional)
    (priority integer :optional)
    (not-before unix-time :optional)
    (deadline unix-time :optional)
    (last-run-at unix-time :optional)
    (next-run-at unix-time :optional)
    (attempts integer :optional)
    (maximum-attempts integer :optional)
    (last-error map :optional))

  (document actor-manifest
    (:extends document
     :persistence persistent)
    (actor string :required)
    (actor-version string :optional)
    (consumer-paths (list string) :optional)
    (target-options map :optional)
    (accepts (list string) :optional)
    (produces (list string) :optional)
    (capabilities (list string) :optional)
    (runtime string :optional)
    (endpoint string :optional)
    (mailbox map :optional)
    (restart-policy string :optional)
    (health-endpoint uri :optional)
    (heartbeat-seconds integer :optional)
    (metadata map :optional))

  (document artifact
    (:extends document
     :persistence persistent)
    (name string :optional)
    (filename string :optional)
    (media-type string :optional)
    (uri uri :optional)
    (storage-uri uri :optional)
    (bytes-hash string :optional)
    (size integer :optional)
    (extracted-text string :optional)
    (ocr-text string :optional)
    (metadata map :optional)
    (attachments (list reference) :optional))

  (document finding
    (:extends document
     :persistence persistent)
    (title string :required)
    (description string :optional)
    (finding-type string :optional)
    (severity string :optional)
    (status string :optional)
    (asset reference :optional)
    (evidence (list reference) :optional)
    (recommendation string :optional)
    (discovered-at unix-time :optional)
    (resolved-at unix-time :optional)
    (cve (list string) :optional)
    (cwe (list string) :optional)
    (cvss map :optional))

  (document scope
    (:extends document
     :persistence persistent)
    (name string :required)
    (program string :optional)
    (in-scope (list string) :optional)
    (out-of-scope (list string) :optional)
    (rules string :optional)
    (starts-at unix-time :optional)
    (ends-at unix-time :optional)
    (rate-limits map :optional)
    (allowed-tools (list string) :optional)
    (prohibited-actions (list string) :optional))

  (predicate related-to
    (:source document
     :destination document))

  (predicate same-as
    (:source document
     :destination document))

  (predicate member-of
    (:source person
     :destination org))

  (predicate employed-by
    (:source person
     :destination org))

  (predicate owns
    (:source document
     :destination document))

  (predicate located-at
    (:source document
     :destination geo))

  (predicate links-to
    (:source url
     :destination url))

  (predicate resolves-to
    (:source domain
     :destination host))

  (predicate hosts-service
    (:source host
     :destination service))

  (predicate belongs-to-asn
    (:source host
     :destination network))

  (predicate leaked-in
    (:source document
     :destination breach))

  (predicate collected-from
    (:source document
     :destination document))

  (predicate derived-from
    (:source document
     :destination document))

  (predicate evidence-of
    (:source artifact
     :destination finding))

  (predicate in-scope-of
    (:source document
     :destination scope))

  (predicate has-finding
    (:source document
     :destination finding))

  (message upsert-document
    (:fields
     ((document reference :required)
      (dataset string :required)
      (run-id string :optional))))

  (message query-documents
    (:fields
     ((dataset string :required)
      (dtype string :optional)
      (filters map :optional)
      (limit integer :optional)
      (cursor string :optional))))

  (message schedule-target
    (:fields
     ((target reference :required)
      (requested-by string :optional))))

  (message actor-manifest-announcement
    (:fields
     ((manifest reference :required)
      (announced-at unix-time :required)))))
