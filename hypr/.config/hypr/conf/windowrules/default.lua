-- Flameshot
hl.window_rule({
	name = "flameshot",
	match = { class = ".*flameshot.*" },
	float = true,
})

-- swaync draws its panel inside a screen-sized layer, so GTK CSS cannot animate
-- the card itself (GTK4 ignores `transform` on .control-center - verified). The
-- compositor does the work instead: `slide` drags the whole surface down from
-- the top edge, which reads as the panel dropping out of the bar. The overshoot
-- comes from the `fluidDrop` curve on layersIn (conf/animations/default.lua).
hl.layer_rule({
	name = "swaync-fluid",
	match = { namespace = "swaync-control-center" },
	animation = "slide",
})

