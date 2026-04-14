if Rails.env.development?
  # Rebuild Tailwind CSS at server startup so newly added utility classes
  # are compiled without needing a separate watcher process.
  # Overhead: ~100ms at boot. New classes take effect on the next server restart.
  require "tailwindcss/commands"
  cmd = Tailwindcss::Commands.compile_command(debug: false)
  system(*cmd, out: File::NULL, err: File::NULL)
end
