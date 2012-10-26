module LoggerHelper

  def log(level, *args)
    if self.respond_to? :logger
      logger.send(level, *args)
    end
  end

end
