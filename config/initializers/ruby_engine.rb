# frozen_string_literal: true

# Announce which Ruby engine is running the ledger (CRuby vs JRuby).
Rails.application.config.after_initialize do
  engine = RUBY_ENGINE
  desc = defined?(RUBY_DESCRIPTION) ? RUBY_DESCRIPTION : "#{engine} #{RUBY_VERSION}"
  msg = "[r_on_rails_ledger] Ruby engine=#{engine} (#{desc})"
  if Rails.logger
    Rails.logger.info(msg)
  else
    warn msg
  end
end
