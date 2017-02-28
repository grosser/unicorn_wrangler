run ->(env) do
  sleep 0.11 if env['PATH_INFO'] == '/slow'
  [200, {}, ["Foo"]]
end
