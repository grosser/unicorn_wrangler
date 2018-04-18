run ->(env) do
  sleep 0.11 if env['PATH_INFO'] == '/slow'
  sleep 0.5 if env['PATH_INFO'] == '/vslow'
  [200, {}, ["Foo #{Process.pid}"]]
end
