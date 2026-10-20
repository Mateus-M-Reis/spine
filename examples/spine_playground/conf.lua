-- LÖVR configuration for Spine Playground
function lovr.conf(t)
    t.window.title = "Spine Playground - Interactive Animation Viewer"
    t.window.width = 1280
    t.window.height = 800

    -- Force desktop (mirror) mode so the example runs on a regular computer.
    t.headset.drivers = { "desktop" }
end
