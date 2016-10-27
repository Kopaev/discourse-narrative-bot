module DiscourseNarrativeBot
  class Narrative
    TRANSITION_TABLE = {
      [:begin, :init] => {
        next_state: :waiting_quote,
        after_action: :say_hello
      },

      [:begin, :reply] => {
        next_state: :waiting_quote,
        after_action: :say_hello
      },

      [:waiting_quote, :reply] => {
        next_state: :tutorial_topic,
        after_action: :quote_user_reply
      },

      [:tutorial_topic, :reply] => {
        next_state: :tutorial_onebox,
        next_instructions_key: 'onebox.instructions',
        after_action: :reply_to_topic
      },

      [:tutorial_onebox, :reply] => {
        next_state: :tutorial_images,
        next_instructions_key: 'images.instructions',
        after_action: :reply_to_onebox
      },

      [:tutorial_images, :reply] => {
        next_state: :tutorial_formatting,
        next_instructions_key: 'formatting.instructions',
        after_action: :reply_to_image
      },

      [:tutorial_formatting, :reply] => {
        next_state: :tutorial_quote,
        next_instructions_key: 'quoting.instructions',
        after_action: :reply_to_formatting
      },

      [:tutorial_quote, :reply] => {
        next_state: :tutorial_emoji,
        next_instructions_key: 'emoji.instructions',
        after_action: :reply_to_quote
      },

      [:tutorial_emoji, :reply] => {
        next_state: :tutorial_mention,
        next_instructions_key: 'mention.instructions',
        after_action: :reply_to_emoji
      },

      [:tutorial_mention, :reply] => {
        next_state: :tutorial_link,
        next_instructions_key: 'link.instructions',
        after_action: :reply_to_mention
      },

      [:tutorial_link, :reply] => {
        next_state: :tutorial_pm,
        next_instructions_key: 'pm.instructions',
        after_action: :reply_to_link
      },

      [:tutorial_pm, :reply] => {
        next_state: :end,
        after_action: :reply_to_pm
      }
    }

    class TransitionError < StandardError; end

    def input(input, user, post)
      @data = DiscourseNarrativeBot::Store.get(user.id) || {}
      @state = (@data[:state] && @data[:state].to_sym) || :begin
      @input = input

      opts = transition(input)
      new_state = opts[:next_state]
      action = opts[:after_action]

      args = { user: user, post: post }

      if next_instructions_key = opts[:next_instructions_key]
        args[:next_instructions_key] = next_instructions_key
      end

      output = self.send(action, args)

      if output
        @data[:state] = new_state
        DiscourseNarrativeBot::Store.set(user.id, @data)

        end_reply if new_state == :end
      end
    end

    private

    def say_hello(user:, post: nil)
      if @input == :init
        reply_to(
          raw: I18n.t(i18n_key('hello'), username: user.username, title: SiteSetting.title),
          topic_id: SiteSetting.discobot_welcome_topic_id
        )
      else
        return unless bot_mentioned?(post)

        reply_to(
          raw: I18n.t(i18n_key('hello'), username: user.username, title: SiteSetting.title),
          topic_id: post.topic.id,
          reply_to_post_number: post.post_number
        )
      end
    end

    def quote_user_reply(user:, post:)
      post_topic_id = post.topic.id
      return unless post_topic_id == SiteSetting.discobot_welcome_topic_id

      fake_delay
      like_post(post)

      reply_to(
        raw: I18n.t(i18n_key('quote_user_reply'),
          username: post.user.username,
          post_id: post.id,
          topic_id: post_topic_id,
          post_raw: post.raw
        ),
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_topic(user:, post:, next_instructions_key:)
      return unless post.topic.category_id == SiteSetting.staff_category_id
      return unless post.is_first_post?

      post_topic_id = post.topic.id
      @data[:topic_id] = post_topic_id

      unless key = post.raw.match(/(unicorn|bacon|ninja|monkey)/i)
        return
      end

      raw = <<~RAW
        #{I18n.t(i18n_key(Regexp.last_match.to_s.downcase))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_onebox(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)

      post.post_analyzer.cook(post.raw, {})
      return unless post.post_analyzer.found_oneboxes?

      raw = <<~RAW
        #{I18n.t(i18n_key('onebox.reply'))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_image(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)

      post.post_analyzer.cook(post.raw, {})
      return unless post.post_analyzer.image_count > 0

      raw = <<~RAW
        #{I18n.t(i18n_key('images.reply'))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_formatting(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(post.cooked)
      return unless doc.css("b", "strong", "em", "i").size > 0

      raw = <<~RAW
        #{I18n.t(i18n_key('formatting.reply'))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_quote(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(post.cooked)
      return unless doc.css(".quote").size > 0

      raw = <<~RAW
        #{I18n.t(i18n_key('quoting.reply'))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_emoji(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(post.cooked)
      return unless doc.css(".emoji").size > 0

      raw = <<~RAW
        #{I18n.t(i18n_key('emoji.reply'))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_mention(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)
      return unless bot_mentioned?(post)

      raw = <<~RAW
        #{I18n.t(i18n_key('mention.reply'))}
        #{I18n.t(i18n_key(next_instructions_key), topic_id: SiteSetting.discobot_welcome_topic_id)}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def bot_mentioned?(post)
      doc = Nokogiri::HTML.fragment(post.cooked)

      valid = false

      doc.css(".mention").each do |mention|
        valid = true if mention.text == "@#{self.class.discobot_user.username}"
      end

      valid
    end

    def reply_to_link(user:, post:, next_instructions_key:)
      post_topic_id = post.topic.id
      return unless valid_topic?(post_topic_id)

      post = post.reload
      post.post_analyzer.cook(post.raw, {})
      return unless post.post_analyzer.link_count > 0

      raw = <<~RAW
        #{I18n.t(i18n_key('link.reply'))}
        #{I18n.t(i18n_key(next_instructions_key))}
      RAW

      fake_delay
      like_post(post)

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: post.post_number
      )
    end

    def reply_to_pm(user:, post:)
      if post.archetype == Archetype.private_message &&
        post.topic.allowed_users.any? { |p| p.id == self.class.discobot_user.id }

        fake_delay
        like_post(post)

        reply_to(
          raw: I18n.t(i18n_key('pm.message')),
          topic_id: post.topic.id,
          reply_to_post_number: post.post_number
        )
      end
    end

    def end_reply
      fake_delay

      reply_to(
        raw: I18n.t(i18n_key('end.message')),
        topic_id: @data[:topic_id]
      )
    end

    def valid_topic?(topic_id)
      topic_id == @data[:topic_id]
    end

    def transition(input)
      TRANSITION_TABLE.fetch([@state, input])
    rescue KeyError
      raise TransitionError.new("No transition from state '#{@state}' for input '#{input}'")
    end

    def i18n_key(key)
      "discourse_narrative_bot.narratives.#{key}"
    end

    def reply_to(opts)
      PostCreator.create!(self.class.discobot_user, opts)
    end

    def fake_delay
      sleep(rand(2..3)) if Rails.env.production?
    end

    def like_post(post)
      PostAction.act(self.class.discobot_user, post, PostActionType.types[:like])
    end

    def self.discobot_user
      @discobot ||= User.find(-2)
    end
  end
end