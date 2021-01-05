class Notification < Ohm::Model
  attribute :state
  attribute :attempts
  attribute :last_send_at
  attribute :video_id
  
  # AASM
  # ===================
  #aasm_column :state
  aasm.attribute_name :state
  
  # States
  #aasm_state :created
  #aasm_state :sending, :after_enter => :process_notification
  #aasm_state :sent
  #aasm_state :failed, :enter => :process_failure
  #aasm_initial_state :created
  aasm column: 'status', no_direct_assignment: true, requires_lock: true do
    state :created, initial: true
    state :sending, :after_enter => :process_notification
    state :sent
    state :failed, :enter => :process_failure

    # Transitions
    event :send_notification do
      transitions :to => :sending, :from => [:created, :failed], :guard => :max_attempts_not_reached?
    end

    event :complete do
      transitions :to => :sent, :from => [:sending]
    end

    event :fail do
      transitions :to => :failed, :from => [:created, :sending]
    end
  end
  
  # Associations
  
  def doc
    @doc ||= Doc[self.doc_id]
  end
  
  
  # Validations
  # ====================
  
  def validate
    assert_present  :state
  end
  
  
  # Sets the Resque Queue
  @queue = :notifications
  
  
  def self.perform(notification_id)
    notification = self[notification_id]
    # set to fail if the guard prevents the state change
    notification.fail! unless notification.send_notification!
  end
  
  def process_notification
    RestClient.post(self.video.client_notification_url, self.to_json, :content_type => :json) { |response|
      #number_of_attempts = self.attempts.blank? ? 1 : self.attempts.to_i + 1
      number_of_attempts = self.attempts.to_s == '' ? 1 : self.attempts.to_i + 1
      self.update(:attempts => number_of_attempts, :last_send_at => Time.now)
      
      case response.code
      when 200
        # notification has succeded
        logger.info("Notification Success")
        self.complete!
      else
        # notification failed
        logger.info("Notification Fail")
        self.fail!
      end  
    }
  end
  
  def process_failure
    # Keep enqueueing if max attempts not reached
    Resque.enqueue(Notification, self.id) if max_attempts_not_reached?
  end
  
  
  # Convenience methods
  # ======================
  
  def to_json
    doc = self.doc
    returning attrs = {} do
      attrs[:doc_id] = doc.id
      attrs[:doc_state] = doc.state
      #attrs[:duration] = doc.duration
      attrs[:doc_thumbnail] = doc.thumbnail_filepath
      attrs[:encodings] = []
      video.doc_encodings.each do |ve|
        attrs[:encodings] << {:id => ve.id.to_i, :filename => ve.filename, :filepath => ve.filepath, :state => ve.state}
      end
    end
    attrs.to_json
  end
  
  
private
  def max_attempts_not_reached?
    #return true if self.attempts.blank?
    return true if self.attempts.to_s == ''
    self.attempts.to_i < monk_settings(:max_notification_attempts)
  end
end
