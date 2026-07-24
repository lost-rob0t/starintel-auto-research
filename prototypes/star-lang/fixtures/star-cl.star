(spec-library "org.starintel/star-cl@1"
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

  (enum id-kind
    (ulid uuidv4 digest supplied))

  (enum id-algorithm
    (md5 sha256))

  (enum collection-status
    (raw normalized enriched verified disputed stale deleted unknown))

  (enum sensitivity
    (public internal confidential restricted secret unknown))

  (enum visibility
    (public private shared inherited unknown))

  (document document
    (:persistence persistent
     :id-policy (:kind ulid))
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
    (source-kinds (list string) :optional)
    (source-license string :optional)
    (source-terms uri :optional)
    (source-retrieved-at unix-time :optional)
    (collected-at unix-time :optional)
    (observed-at unix-time :optional)
    (first-seen-at unix-time :optional)
    (last-seen-at unix-time :optional)
    (created-at unix-time :required)
    (updated-at unix-time :required)
    (date-added unix-time :required)
    (date-updated unix-time :required)
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
    (hash-algorithm id-algorithm :optional)
    (normalized-hash string :optional)
    (raw map :optional)
    (raw-content string :optional)
    (notes string :optional)
    (deleted boolean :optional)
    (tombstone-reason string :optional)
    (extensions map :optional))

  (document person
    (:extends document
     :persistence persistent
     :id-policy (:kind ulid))
    (fname string :optional)
    (mname string :optional)
    (lname string :optional)
    (full-name string :optional)
    (display-name string :optional)
    (prefix string :optional)
    (suffix string :optional)
    (bio string :optional)
    (dob iso-date :optional)
    (date-of-death iso-date :optional)
    (age integer :optional)
    (gender string :optional)
    (pronouns string :optional)
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
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (name reg country)))
    (reg string :optional)
    (name string :required)
    (legal-name string :optional)
    (aliases (list string) :optional)
    (bio string :optional)
    (country string :optional)
    (jurisdiction string :optional)
    (website uri :optional)
    (registration-number string :optional)
    (tax-id string :optional)
    (industry (list string) :optional)
    (founded-at iso-date :optional)
    (dissolved-at iso-date :optional)
    (status string :optional)
    (parent-org reference :optional)
    (subsidiaries (list reference) :optional)
    (addresses (list reference) :optional)
    (phones (list reference) :optional)
    (emails (list reference) :optional)
    (accounts (list reference) :optional)
    (etype string :optional)
    (eid string :optional))

  (document relation
    (:extends document
     :persistence persistent
     :id-policy (:kind ulid))
    (source document-id :required)
    (target document-id :required)
    (predicate string :required)
    (note string :optional)
    (direction string :optional)
    (inverse-predicate string :optional)
    (weight confidence-score :optional)
    (evidence (list reference) :optional)
    (asserted-at unix-time :optional)
    (asserted-by string :optional)
    (valid-from unix-time :optional)
    (valid-until unix-time :optional))

  (document domain
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (record record-type)))
    (record-type string :optional)
    (record string :required)
    (fqdn string :optional)
    (registrable-domain string :optional)
    (subdomain string :optional)
    (tld string :optional)
    (unicode-name string :optional)
    (punycode-name string :optional)
    (resolved-addresses (list string) :optional)
    (dns-records (list map) :optional)
    (nameservers (list string) :optional)
    (mx-records (list map) :optional)
    (txt-records (list string) :optional)
    (whois map :optional)
    (registrar string :optional)
    (registered-at iso-datetime :optional)
    (expires-at iso-datetime :optional))

  (document service
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (host port transport name version)))
    (host reference :optional)
    (port port-number :required)
    (transport string :optional)
    (name string :optional)
    (product string :optional)
    (version string :optional)
    (banner string :optional)
    (protocol string :optional)
    (tls boolean :optional)
    (tls-certificate reference :optional)
    (state string :optional)
    (fingerprints map :optional))

  (document port
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (host port protocol)))
    (host reference :optional)
    (port port-number :required)
    (protocol string :optional)
    (state string :optional)
    (service reference :optional)
    (reason string :optional)
    (observed-by string :optional))

  (document network
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (asn org subnet)))
    (org string :optional)
    (subnet string :required)
    (asn asn-number :optional)
    (cidr string :optional)
    (network-address string :optional)
    (broadcast-address string :optional)
    (prefix-length integer :optional)
    (rir string :optional)
    (country string :optional)
    (description string :optional))

  (document asn
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (number)))
    (number asn-number :required)
    (name string :optional)
    (organization string :optional)
    (country string :optional)
    (rir string :optional)
    (subnets (list string) :optional)
    (peers (list asn-number) :optional)
    (upstreams (list asn-number) :optional)
    (downstreams (list asn-number) :optional))

  (document host
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (ip)))
    (hostname string :optional)
    (ip string :required)
    (ip-version integer :optional)
    (reverse-dns (list string) :optional)
    (os string :optional)
    (os-version string :optional)
    (mac-address string :optional)
    (ports (list reference) :optional)
    (services (list reference) :optional)
    (network reference :optional)
    (asn reference :optional)
    (location reference :optional)
    (cloud map :optional)
    (virtualization string :optional))

  (document url
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (url content)))
    (url uri :required)
    (scheme string :optional)
    (host string :optional)
    (port port-number :optional)
    (path string :optional)
    (query string :optional)
    (fragment string :optional)
    (content string :optional)
    (title string :optional)
    (status-code integer :optional)
    (headers map :optional)
    (redirect-chain (list uri) :optional)
    (canonical-url uri :optional)
    (technologies (list string) :optional)
    (forms (list map) :optional)
    (links (list uri) :optional)
    (screenshots (list reference) :optional))

  (document breach
    (:extends document
     :persistence persistent)
    (name string :optional)
    (total integer :optional)
    (description string :optional)
    (url uri :optional)
    (breached-at iso-date :optional)
    (published-at iso-date :optional)
    (data-classes (list string) :optional)
    (verified boolean :optional)
    (sensitive boolean :optional)
    (records (list reference) :optional))

  (document email
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (user domain password)))
    (address string :optional)
    (user string :required)
    (domain string :required)
    (password string :optional)
    (display-name string :optional)
    (valid boolean :optional)
    (deliverable boolean :optional)
    (disposable boolean :optional)
    (role-address boolean :optional)
    (mx-hosts (list string) :optional)
    (breaches (list reference) :optional)
    (credentials (list map) :optional))

  (document email-message
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (body to from subject)))
    (body string :optional)
    (subject string :optional)
    (to (list string) :optional)
    (from string :optional)
    (reply-to string :optional)
    (headers map :optional)
    (cc (list string) :optional)
    (bcc (list string) :optional)
    (message-id string :optional)
    (in-reply-to string :optional)
    (references (list string) :optional)
    (sent-at iso-datetime :optional)
    (received-at iso-datetime :optional)
    (attachments (list reference) :optional))

  (document user
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (name url platform)))
    (url uri :optional)
    (name string :required)
    (display-name string :optional)
    (platform string :required)
    (platform-id string :optional)
    (bio string :optional)
    (misc (list map) :optional)
    (avatar reference :optional)
    (created-at-platform iso-datetime :optional)
    (followers-count integer :optional)
    (following-count integer :optional)
    (posts-count integer :optional)
    (verified boolean :optional)
    (private boolean :optional)
    (status string :optional))

  (document phone
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (number)))
    (number string :required)
    (e164 string :optional)
    (country-code string :optional)
    (national-number string :optional)
    (extension string :optional)
    (carrier string :optional)
    (status string :optional)
    (phone-type string :optional)
    (valid boolean :optional)
    (possible boolean :optional)
    (location string :optional)
    (timezone (list string) :optional))

  (document geo
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (lat long alt)))
    (lat latitude :required)
    (long longitude :required)
    (alt decimal :optional)
    (accuracy decimal :optional)
    (geohash string :optional)
    (coordinate-system string :optional))

  (document address
    (:extends geo
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (lat long alt city state postal country street street2)))
    (city string :optional)
    (state string :optional)
    (county string :optional)
    (postal string :optional)
    (country string :optional)
    (country-code string :optional)
    (street string :optional)
    (street2 string :optional)
    (formatted string :optional)
    (building string :optional)
    (unit string :optional)
    (neighborhood string :optional))

  (document message
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (content user channel group message-id platform)))
    (content string :required)
    (platform string :optional)
    (user reference :optional)
    (is-reply boolean :optional)
    (media (list reference) :optional)
    (message-id string :optional)
    (reply-to reference :optional)
    (group string :optional)
    (channel string :optional)
    (mentions (list reference) :optional)
    (reactions map :optional)
    (sent-at iso-datetime :optional)
    (edited-at iso-datetime :optional)
    (deleted-at iso-datetime :optional))

  (document socialmpost
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (content user url group)))
    (content string :required)
    (user reference :optional)
    (platform string :optional)
    (platform-id string :optional)
    (replies (list reference) :optional)
    (media (list reference) :optional)
    (reply-count integer :optional)
    (repost-count integer :optional)
    (like-count integer :optional)
    (view-count integer :optional)
    (url uri :optional)
    (links (list uri) :optional)
    (tags (list string) :optional)
    (title string :optional)
    (group string :optional)
    (reply-to reference :optional)
    (published-at iso-datetime :optional)
    (edited-at iso-datetime :optional))

  (document target
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (dataset target actor)))
    (actor string :required)
    (target string :required)
    (delay integer :optional)
    (recurring boolean :optional)
    (schedule string :optional)
    (options map :optional)
    (scope reference :optional)
    (priority integer :optional)
    (state string :optional)
    (next-run-at unix-time :optional)
    (last-run-at unix-time :optional))

  (document actor-manifest
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (actor)))
    (actor string :required)
    (runtime string :optional)
    (version string :optional)
    (consumer-paths (list string) :optional)
    (target-options map :optional)
    (accepts (list string) :optional)
    (produces (list string) :optional)
    (capabilities (list string) :optional)
    (mailbox map :optional)
    (restart-policy string :optional)
    (endpoint string :optional)
    (health-endpoint string :optional))

  (document scope
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (name in out)))
    (name string :required)
    (description string :optional)
    (in (list string) :optional)
    (out (list string) :optional)
    (constraints map :optional)
    (authorization map :optional)
    (starts-at unix-time :optional)
    (ends-at unix-time :optional))

  (document artifact
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm sha256
                 :fields (content-hash source-url name)))
    (name string :optional)
    (artifact-type string :optional)
    (source-url uri :optional)
    (path string :optional)
    (content-hash string :required)
    (mime-type string :optional)
    (size-bytes integer :optional)
    (created-by string :optional)
    (tool string :optional)
    (tool-version string :optional))

  (document finding
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm sha256
                 :fields (target title evidence)))
    (target reference :required)
    (title string :required)
    (description string :optional)
    (severity string :optional)
    (confidence confidence-score :optional)
    (status string :optional)
    (evidence (list reference) :optional)
    (remediation string :optional)
    (references (list uri) :optional))

  (document runtime-event
    (:extends document
     :persistence transient
     :id-policy (:kind uuidv4))
    (event-type string :required)
    (actor string :optional)
    (payload map :optional)
    (occurred-at unix-time :required))

  (message generate-id
    (:fields
     ((kind id-kind :required)
      (algorithm id-algorithm :optional)
      (value any :optional)
      (fields (list string) :optional)
      (prefix string :optional))))

  (message create-document
    (:fields
     ((document-type string :required)
      (dataset string :required)
      (values map :required))))

  (message encode-document
    (:fields
     ((document reference :required)
      (key-style string :optional)
      (couchdb boolean :optional))))

  (message decode-document
    (:fields
     ((document-type string :required)
      (encoded map :required)
      (dataset string :optional))))

  (message relate-documents
    (:fields
     ((source reference :required)
      (target reference :required)
      (predicate string :required)
      (note string :optional)))))
