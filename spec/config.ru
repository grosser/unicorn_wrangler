run ->(env) do
  sleep 0.1 if env['PATH_INFO'] == '/slow'
  [200, {}, ["Foo"]]
end
