;; SkillGrid Growth Tracker - skill-grid contract
;; This contract manages user skill matrices, progress tracking, and visibility settings for the SkillGrid platform.
;; It allows users to create, update, and visualize their skill development journey with full control over data visibility.

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-VISIBILITY-SETTING (err u104))
(define-constant ERR-GOAL-EXPIRED (err u105))
(define-constant ERR-INVALID-PROFICIENCY (err u106))

;; Constants
(define-constant MAX-PROFICIENCY-LEVEL u5) ;; 1 = beginner, 5 = expert
(define-constant VISIBILITY-PRIVATE u1)
(define-constant VISIBILITY-SHARED u2)
(define-constant VISIBILITY-PUBLIC u3)

;; Data structures

;; Track all users that have created a skill grid
(define-map users
  principal
  {
    created-at: uint,
    skill-count: uint
  }
)

;; Store skill definitions created by users
(define-map skills
  {
    user: principal,
    skill-id: uint
  }
  {
    name: (string-ascii 50),
    category: (string-ascii 30),
    description: (string-utf8 500),
    created-at: uint,
    visibility: uint, ;; 1=private, 2=shared, 3=public
    current-proficiency: uint,
    last-updated: uint
  }
)

;; Store historical progress updates for each skill
(define-map skill-updates
  {
    user: principal,
    skill-id: uint,
    update-id: uint
  }
  {
    proficiency: uint,
    timestamp: uint,
    evidence: (string-utf8 500), ;; Optional evidence of progress
    milestone: (string-utf8 100)  ;; Optional milestone description
  }
)

;; Store skill goals set by users
(define-map skill-goals
  {
    user: principal,
    skill-id: uint,
    goal-id: uint
  }
  {
    target-proficiency: uint,
    target-date: uint,
    description: (string-utf8 200),
    created-at: uint,
    completed: bool,
    completed-at: uint
  }
)

;; Track addresses that have access to a user's shared skills
(define-map shared-access
  {
    owner: principal,
    viewer: principal
  }
  {
    granted-at: uint,
    can-view: bool
  }
)

;; Counter for skill IDs per user
(define-map skill-id-counter principal uint)

;; Counter for update IDs per skill
(define-map update-id-counter 
  {
    user: principal,
    skill-id: uint
  }
  uint
)

;; Counter for goal IDs per skill
(define-map goal-id-counter
  {
    user: principal,
    skill-id: uint
  }
  uint
)

;; Private functions

;; Get the next skill ID for a user
(define-private (get-next-skill-id (user principal))
  (let ((current-id (default-to u0 (map-get? skill-id-counter user))))
    (begin
      (map-set skill-id-counter user (+ current-id u1))
      (+ current-id u1))))

;; Get the next update ID for a skill
(define-private (get-next-update-id (user principal) (skill-id uint))
  (let ((current-id (default-to u0 (map-get? update-id-counter {user: user, skill-id: skill-id}))))
    (begin
      (map-set update-id-counter {user: user, skill-id: skill-id} (+ current-id u1))
      (+ current-id u1))))

;; Get the next goal ID for a skill
(define-private (get-next-goal-id (user principal) (skill-id uint))
  (let ((current-id (default-to u0 (map-get? goal-id-counter {user: user, skill-id: skill-id}))))
    (begin
      (map-set goal-id-counter {user: user, skill-id: skill-id} (+ current-id u1))
      (+ current-id u1))))

;; Check if a proficiency level is valid (1-5)
(define-private (is-valid-proficiency (level uint))
  (<= level MAX-PROFICIENCY-LEVEL))

;; Check if a visibility setting is valid
(define-private (is-valid-visibility (visibility uint))
  (or
    (is-eq visibility VISIBILITY-PRIVATE)
    (is-eq visibility VISIBILITY-SHARED)
    (is-eq visibility VISIBILITY-PUBLIC)))

;; Check if caller has access to view a skill
(define-private (can-view-skill (owner principal) (skill-data {name: (string-ascii 50), category: (string-ascii 30), description: (string-utf8 500), created-at: uint, visibility: uint, current-proficiency: uint, last-updated: uint}))
  (or
    (is-eq tx-sender owner) ;; Owner can always view
    (is-eq (get visibility skill-data) VISIBILITY-PUBLIC) ;; Public skills can be viewed by anyone
    (and
      (is-eq (get visibility skill-data) VISIBILITY-SHARED)
      (default-to false (get can-view (map-get? shared-access {owner: owner, viewer: tx-sender})))))) ;; Check if viewer has shared access

;; Read-only functions

;; Get user profile information
(define-read-only (get-user-info (user principal))
  (default-to
    {created-at: u0, skill-count: u0}
    (map-get? users user)))

;; Get skill information if authorized to view
(define-read-only (get-skill (owner principal) (skill-id uint))
  (let ((skill-data (map-get? skills {user: owner, skill-id: skill-id})))
    (if (and (is-some skill-data) (can-view-skill owner (unwrap-panic skill-data)))
      skill-data
      none)))

;; Get skill update history if authorized to view
(define-read-only (get-skill-updates (owner principal) (skill-id uint))
  (let ((skill-data (map-get? skills {user: owner, skill-id: skill-id})))
    (if (and (is-some skill-data) (can-view-skill owner (unwrap-panic skill-data)))
      (some true) ;; In a real implementation, this would return actual update history
      none)))

;; Check if caller has shared access to a user's skills
(define-read-only (has-shared-access (owner principal) (viewer principal))
  (default-to
    {granted-at: u0, can-view: false}
    (map-get? shared-access {owner: owner, viewer: viewer})))

;; Get skill goals if authorized to view
(define-read-only (get-skill-goals (owner principal) (skill-id uint))
  (let ((skill-data (map-get? skills {user: owner, skill-id: skill-id})))
    (if (and (is-some skill-data) (can-view-skill owner (unwrap-panic skill-data)))
      (some true) ;; In a real implementation, this would return actual goals
      none)))

;; Public functions

;; Create a new user profile
(define-public (initialize-user)
  (let ((user-exists (map-get? users tx-sender)))
    (if (is-some user-exists)
      ERR-ALREADY-EXISTS
      (begin
        (map-set users tx-sender {
          created-at: block-height,
          skill-count: u0
        })
        (ok true)))))

;; Add a new skill to the user's skill grid
(define-public (add-skill (name (string-ascii 50)) (category (string-ascii 30)) (description (string-utf8 500)) (visibility uint) (initial-proficiency uint))
  (let (
    (user-data (map-get? users tx-sender))
    (skill-id (get-next-skill-id tx-sender))
  )
    (asserts! (is-some user-data) ERR-NOT-FOUND)
    (asserts! (is-valid-visibility visibility) ERR-VISIBILITY-SETTING)
    (asserts! (and (> initial-proficiency u0) (is-valid-proficiency initial-proficiency)) ERR-INVALID-PROFICIENCY)
    
    ;; Create the new skill entry
    (map-set skills 
      {user: tx-sender, skill-id: skill-id}
      {
        name: name,
        category: category,
        description: description,
        created-at: block-height,
        visibility: visibility,
        current-proficiency: initial-proficiency,
        last-updated: block-height
      }
    )
    
    ;; Create initial progress update
    (map-set skill-updates
      {user: tx-sender, skill-id: skill-id, update-id: u1}
      {
        proficiency: initial-proficiency,
        timestamp: block-height,
        evidence: "",
        milestone: "Initial skill level set"
      }
    )
    
    ;; Update user's skill count
    (map-set users 
      tx-sender 
      {
        created-at: (get created-at (unwrap-panic user-data)),
        skill-count: (+ (get skill-count (unwrap-panic user-data)) u1)
      }
    )
    
    (ok skill-id)))

;; Update a skill's proficiency and add evidence
(define-public (update-skill-progress (skill-id uint) (new-proficiency uint) (evidence (string-utf8 500)) (milestone (string-utf8 100)))
  (let (
    (skill-data (map-get? skills {user: tx-sender, skill-id: skill-id}))
    (update-id (get-next-update-id tx-sender skill-id))
  )
    (asserts! (is-some skill-data) ERR-NOT-FOUND)
    (asserts! (and (> new-proficiency u0) (is-valid-proficiency new-proficiency)) ERR-INVALID-PROFICIENCY)
    
    ;; Create new progress update
    (map-set skill-updates
      {user: tx-sender, skill-id: skill-id, update-id: update-id}
      {
        proficiency: new-proficiency,
        timestamp: block-height,
        evidence: evidence,
        milestone: milestone
      }
    )
    
    ;; Update the skill's current proficiency
    (map-set skills
      {user: tx-sender, skill-id: skill-id}
      (merge (unwrap-panic skill-data)
        {
          current-proficiency: new-proficiency,
          last-updated: block-height
        }
      )
    )
    
    (ok update-id)))

;; Change visibility settings for a skill
(define-public (set-skill-visibility (skill-id uint) (visibility uint))
  (let ((skill-data (map-get? skills {user: tx-sender, skill-id: skill-id})))
    (asserts! (is-some skill-data) ERR-NOT-FOUND)
    (asserts! (is-valid-visibility visibility) ERR-VISIBILITY-SETTING)
    
    (map-set skills
      {user: tx-sender, skill-id: skill-id}
      (merge (unwrap-panic skill-data)
        {
          visibility: visibility
        }
      )
    )
    
    (ok true)))

;; Grant access to a specific user to view shared skills
(define-public (grant-access (viewer principal))
  (begin
    (map-set shared-access
      {owner: tx-sender, viewer: viewer}
      {
        granted-at: block-height,
        can-view: true
      }
    )
    (ok true)))

;; Revoke access from a specific user
(define-public (revoke-access (viewer principal))
  (begin
    (map-set shared-access
      {owner: tx-sender, viewer: viewer}
      {
        granted-at: block-height,
        can-view: false
      }
    )
    (ok true)))

;; Set a goal for a specific skill
(define-public (set-skill-goal (skill-id uint) (target-proficiency uint) (target-date uint) (description (string-utf8 200)))
  (let (
    (skill-data (map-get? skills {user: tx-sender, skill-id: skill-id}))
    (goal-id (get-next-goal-id tx-sender skill-id))
  )
    (asserts! (is-some skill-data) ERR-NOT-FOUND)
    (asserts! (and (> target-proficiency u0) (is-valid-proficiency target-proficiency)) ERR-INVALID-PROFICIENCY)
    (asserts! (> target-date block-height) ERR-INVALID-INPUT)
    
    (map-set skill-goals
      {user: tx-sender, skill-id: skill-id, goal-id: goal-id}
      {
        target-proficiency: target-proficiency,
        target-date: target-date,
        description: description,
        created-at: block-height,
        completed: false,
        completed-at: u0
      }
    )
    
    (ok goal-id)))

;; Mark a goal as completed
(define-public (complete-goal (skill-id uint) (goal-id uint))
  (let (
    (goal-data (map-get? skill-goals {user: tx-sender, skill-id: skill-id, goal-id: goal-id}))
  )
    (asserts! (is-some goal-data) ERR-NOT-FOUND)
    (asserts! (not (get completed (unwrap-panic goal-data))) ERR-INVALID-INPUT)
    
    (map-set skill-goals
      {user: tx-sender, skill-id: skill-id, goal-id: goal-id}
      (merge (unwrap-panic goal-data)
        {
          completed: true,
          completed-at: block-height
        }
      )
    )
    
    (ok true)))