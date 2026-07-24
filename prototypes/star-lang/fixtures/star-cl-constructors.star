(spec-library "org.starintel/star-cl-constructors@1"
  (:version "1.0.0"
   :generate-default-constructors t
   :constructors
   ((new-org
     (:document org
      :lambda-list (dataset name etype &rest args)
      :dataset dataset
      :bindings ((name name) (etype etype))
      :rest-keywords args
      :validate nil))

    (new-person
     (:document person
      :lambda-list (dataset fname lname etype &rest args)
      :dataset dataset
      :bindings ((fname fname) (lname lname) (etype etype))
      :rest-keywords args
      :validate nil))

    (new-domain
     (:document domain
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-port
     (:document port
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-asn
     (:document asn
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-network
     (:document network
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-host
     (:document host
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-url
     (:document url
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-email
     (:document email
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-email*
     (:document email
      :lambda-list (dataset email &rest args)
      :dataset dataset
      :bindings ((user (:email-user email))
                 (domain (:email-domain email)))
      :rest-keywords args
      :validate nil))

    (new-user
     (:document user
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-username
     (:document user
      :lambda-list (dataset name &rest args)
      :dataset dataset
      :bindings ((name name))
      :rest-keywords args
      :validate nil))

    (new-phone
     (:document phone
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-message
     (:document message
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-social-media-post
     (:document socialmpost
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-geo
     (:document geo
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-address
     (:document address
      :lambda-list (dataset &rest args)
      :dataset dataset
      :rest-keywords args
      :validate nil))

    (new-relation
     (:document relation
      :lambda-list (dataset source target &key note (predicate "related-to"))
      :dataset dataset
      :bindings ((source source)
                 (target target)
                 (predicate predicate)
                 (note (:or note "")))
      :validator relation-predicate
      :validate nil))

    (new-target
     (:document target
      :lambda-list (dataset target actor
                    &key (options nil) (delay 0) (recurring nil))
      :dataset dataset
      :bindings ((target target)
                 (actor actor)
                 (options options)
                 (delay delay)
                 (recurring recurring))
      :validate nil))

    (new-target-without-options
     (:document target
      :lambda-list (dataset target actor)
      :dataset dataset
      :bindings ((target target)
                 (actor actor)
                 (options nil)
                 (delay 0)
                 (recurring nil))
      :validate nil))))

  (import "org.starintel/star-cl@1"
    :version "1.0.0"
    :digest "sha256:078ba09687c8ccbba8fa10e40cd96438d2ad3ade0c1f0e3813902e85e812113d"
    :path "star-cl.star"))
