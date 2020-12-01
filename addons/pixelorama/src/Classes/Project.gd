tool
class_name Project extends Reference
# A class for project properties.

var global = null
var name := "" setget name_changed
var size : Vector2 setget size_changed
var undo_redo : UndoRedo
var Constants = preload("res://addons/pixelorama/src/Autoload/Constants.gd")
var tile_mode : int = Constants.Tile_Mode.NONE
var undos := 0 # The number of times we added undo properties
var has_changed := false setget has_changed_changed
var frames := [] setget frames_changed # Array of Frames (that contain Cels)
var frame_duration := []
var layers := [] setget layers_changed # Array of Layers
var current_frame := 0 setget frame_changed
var current_layer := 0 setget layer_changed
var animation_tags := [] setget animation_tags_changed # Array of AnimationTags
var guides := [] # Array of Guides

var brushes := [] # Array of Images

var x_symmetry_point
var y_symmetry_point
var x_symmetry_axis : SymmetryGuide
var y_symmetry_axis : SymmetryGuide

var selected_pixels := []
var selected_rect := Rect2(0, 0, 0, 0) setget _set_selected_rect

# For every camera (currently there are 3)
var cameras_zoom := [Vector2(0.15, 0.15), Vector2(0.15, 0.15), Vector2(0.15, 0.15)] # Array of Vector2
var cameras_offset := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO] # Array of Vector2

# Export directory path and export file name
var directory_path := ""
var file_name := "untitled"
var file_format : int = Constants.FileFormat.PNG
var was_exported := false


func _init(_frames := [], _name := tr("untitled"), _size := Vector2(64, 64), p_global = null) -> void:
	global = p_global
	frames = _frames
	name = _name
	size = _size
	frame_duration.append(1)
	select_all_pixels()

	undo_redo = UndoRedo.new()

	global.tabs.add_tab(name)
	global.get_open_save().current_save_paths.append("")
	global.get_open_save().backup_save_paths.append("")

	x_symmetry_point = size.x / 2
	y_symmetry_point = size.y / 2

	if !x_symmetry_axis:
		x_symmetry_axis = SymmetryGuide.new()
		x_symmetry_axis.type = x_symmetry_axis.Types.HORIZONTAL
		x_symmetry_axis.project = self
		x_symmetry_axis.add_point(Vector2(-19999, y_symmetry_point))
		x_symmetry_axis.add_point(Vector2(19999, y_symmetry_point))
		global.canvas.add_child(x_symmetry_axis)

	if !y_symmetry_axis:
		y_symmetry_axis = SymmetryGuide.new()
		y_symmetry_axis.type = y_symmetry_axis.Types.VERTICAL
		y_symmetry_axis.project = self
		y_symmetry_axis.add_point(Vector2(x_symmetry_point, -19999))
		y_symmetry_axis.add_point(Vector2(x_symmetry_point, 19999))
		global.canvas.add_child(y_symmetry_axis)

	if OS.get_name() == "HTML5":
		directory_path = "user://"
	else:
		directory_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)


func select_all_pixels() -> void:
	clear_selection()
	for x in size.x:
		for y in size.y:
			selected_pixels.append(Vector2(x, y))


func clear_selection() -> void:
	selected_pixels.clear()


func _set_selected_rect(value : Rect2) -> void:
	selected_rect = value
	global.selection_rectangle.set_rect(value)


func change_project() -> void:
	# Remove old nodes
	for container in global.layers_container.get_children():
		container.queue_free()

	remove_cel_buttons()

	for frame_id in global.frame_ids.get_children():
		global.frame_ids.remove_child(frame_id)
		frame_id.queue_free()

	# Create new ones
	for i in range(layers.size() - 1, -1, -1):
		# Create layer buttons
		var layer_container = load("res://addons/pixelorama/src/UI/Timeline/LayerButton.tscn").instance()
		layer_container.i = i
		if layers[i].name == tr("Layer") + " 0":
			layers[i].name = tr("Layer") + " %s" % i

		global.layers_container.add_child(layer_container)
		layer_container.label.text = layers[i].name
		layer_container.line_edit.text = layers[i].name

		global.frames_container.add_child(layers[i].frame_container)
		for j in range(frames.size()): # Create Cel buttons
			var cel_button = load("res://addons/pixelorama/src/UI/Timeline/CelButton.tscn").instance()
			cel_button.frame = j
			cel_button.layer = i
			cel_button.get_child(0).texture = frames[j].cels[i].image_texture
			if j == current_frame and i == current_layer:
				cel_button.pressed = true

			layers[i].frame_container.add_child(cel_button)

	for j in range(frames.size()): # Create frame ID labels
		var label := Label.new()
		label.rect_min_size.x = 36
		label.align = Label.ALIGN_CENTER
		label.text = str(j + 1)
		if j == current_frame:
			label.add_color_override("font_color", global.control.theme.get_color("Selected Color", "Label"))
		global.frame_ids.add_child(label)

	var layer_button = global.layers_container.get_child(global.layers_container.get_child_count() - 1 - current_layer)
	layer_button.pressed = true

	global.current_frame_mark_label.text = "%s/%s" % [str(current_frame + 1), frames.size()]

	global.disable_button(global.remove_frame_button, frames.size() == 1)
	global.disable_button(global.move_left_frame_button, frames.size() == 1 or current_frame == 0)
	global.disable_button(global.move_right_frame_button, frames.size() == 1 or current_frame == frames.size() - 1)
	toggle_layer_buttons_layers()
	toggle_layer_buttons_current_layer()

	self.animation_tags = animation_tags

	# Change the selection rectangle
	global.selection_rectangle.set_rect(selected_rect)

	# Change the guides
	for guide in global.canvas.get_children():
		if guide is Guide:
			if guide in guides:
				guide.visible = global.show_guides
				if guide is SymmetryGuide:
					if guide.type == Guide.Types.HORIZONTAL:
						guide.visible = global.show_x_symmetry_axis and global.show_guides
					else:
						guide.visible = global.show_y_symmetry_axis and global.show_guides
			else:
				guide.visible = false

	# Change the project brushes
	Brushes.clear_project_brush(global.brushes_popup)
	for brush in brushes:
		Brushes.add_project_brush(global.brushes_popup ,brush)

	var cameras = [global.camera, global.camera2, global.camera_preview]
	var i := 0
	for camera in cameras:
		camera.zoom = cameras_zoom[i]
		camera.offset = cameras_offset[i]
		i += 1
	global.zoom_level_label.text = str(round(100 / global.camera.zoom.x)) + " %"
	global.canvas.update()
	global.canvas.grid.isometric_polylines.clear()
	global.canvas.grid.update()
	global.transparent_checker._enter_tree()
	global.horizontal_ruler.update()
	global.vertical_ruler.update()
	global.preview_zoom_slider.value = -global.camera_preview.zoom.x
	global.cursor_position_label.text = "[%s×%s]" % [size.x, size.y]

	global.window_title = "%s - Pixelorama %s" % [name, global.current_version]
	if has_changed:
		global.window_title = global.window_title + "(*)"

	var save_path = global.get_open_save().current_save_paths[global.current_project_index]
	if save_path != "":
		global.open_sprites_dialog.current_path = save_path
		global.save_sprites_dialog.current_path = save_path
		global.file_menu.get_popup().set_item_text(4, tr("Save") + " %s" % save_path.get_file())
	else:
		global.file_menu.get_popup().set_item_text(4, tr("Save"))

	global.get_export().directory_path = directory_path
	global.get_export().file_name = file_name
	global.get_export().file_format = file_format
	global.get_export().was_exported = was_exported

	if !was_exported:
		global.file_menu.get_popup().set_item_text(6, tr("Export"))
	else:
		global.file_menu.get_popup().set_item_text(6, tr("Export") + " %s" % (file_name + global.get_export().file_format_string(file_format)))


func serialize() -> Dictionary:
	var layer_data := []
	for layer in layers:
		var linked_cels := []
		for cel in layer.linked_cels:
			linked_cels.append(frames.find(cel))

		layer_data.append({
			"name" : layer.name,
			"visible" : layer.visible,
			"locked" : layer.locked,
			"new_cels_linked" : layer.new_cels_linked,
			"linked_cels" : linked_cels,
		})

	var tag_data := []
	for tag in animation_tags:
		tag_data.append({
			"name" : tag.name,
			"color" : tag.color.to_html(),
			"from" : tag.from,
			"to" : tag.to,
		})

	var guide_data := []
	for guide in guides:
		if guide is SymmetryGuide:
			continue
		if !is_instance_valid(guide):
			continue
		var coords = guide.points[0].x
		if guide.type == Guide.Types.HORIZONTAL:
			coords = guide.points[0].y

		guide_data.append({"type" : guide.type, "pos" : coords})

	var frame_data := []
	for frame in frames:
		var cel_data := []
		for cel in frame.cels:
			cel_data.append({
				"opacity" : cel.opacity,
#				"image_data" : cel.image.get_data()
			})
		frame_data.append({
			"cels" : cel_data
		})
	var brush_data := []
	for brush in brushes:
		brush_data.append({
			"size_x" : brush.get_size().x,
			"size_y" : brush.get_size().y
		})

	var project_data := {
		"pixelorama_version" : global.current_version,
		"name" : name,
		"size_x" : size.x,
		"size_y" : size.y,
		"save_path" : global.get_open_save().current_save_paths[global.projects.find(self)],
		"layers" : layer_data,
		"tags" : tag_data,
		"guides" : guide_data,
		"symmetry_points" : [x_symmetry_point, y_symmetry_point],
		"frames" : frame_data,
		"brushes" : brush_data,
		"export_directory_path" : directory_path,
		"export_file_name" : file_name,
		"export_file_format" : file_format,
		"frame_duration" : frame_duration,
	}

	return project_data


func deserialize(dict : Dictionary) -> void:
	if dict.has("name"):
		name = dict.name
	if dict.has("size_x") and dict.has("size_y"):
		size.x = dict.size_x
		size.y = dict.size_y
		select_all_pixels()
	if dict.has("save_path"):
		global.get_open_save().current_save_paths[global.projects.find(self)] = dict.save_path
	if dict.has("frames"):
		for frame in dict.frames:
			var cels := []
			for cel in frame.cels:
				cels.append(Cel.new(Image.new(), cel.opacity))
			frames.append(Frame.new(cels))
		if dict.has("layers"):
			var layer_i :=  0
			for saved_layer in dict.layers:
				var linked_cels := []
				for linked_cel_number in saved_layer.linked_cels:
					linked_cels.append(frames[linked_cel_number])
					frames[linked_cel_number].cels[layer_i].image = linked_cels[0].cels[layer_i].image
					frames[linked_cel_number].cels[layer_i].image_texture = linked_cels[0].cels[layer_i].image_texture
				var layer := Layer.new(saved_layer.name, saved_layer.visible, saved_layer.locked, HBoxContainer.new(), saved_layer.new_cels_linked, linked_cels)
				layers.append(layer)
				layer_i += 1
	if dict.has("tags"):
		for tag in dict.tags:
			animation_tags.append(AnimationTag.new(tag.name, Color(tag.color), tag.from, tag.to))
		self.animation_tags = animation_tags
	if dict.has("guides"):
		for g in dict.guides:
			var guide := Guide.new()
			guide.type = g.type
			if guide.type == Guide.Types.HORIZONTAL:
				guide.add_point(Vector2(-99999, g.pos))
				guide.add_point(Vector2(99999, g.pos))
			else:
				guide.add_point(Vector2(g.pos, -99999))
				guide.add_point(Vector2(g.pos, 99999))
			guide.has_focus = false
			guide.project = self
			global.canvas.add_child(guide)
	if dict.has("symmetry_points"):
		x_symmetry_point = dict.symmetry_points[0]
		y_symmetry_point = dict.symmetry_points[1]
		x_symmetry_axis.points[0].y = floor(y_symmetry_point / 2 + 1)
		x_symmetry_axis.points[1].y = floor(y_symmetry_point / 2 + 1)
		y_symmetry_axis.points[0].x = floor(x_symmetry_point / 2 + 1)
		y_symmetry_axis.points[1].x = floor(x_symmetry_point / 2 + 1)
	if dict.has("export_directory_path"):
		directory_path = dict.export_directory_path
	if dict.has("export_file_name"):
		file_name = dict.export_file_name
	if dict.has("export_file_format"):
		file_format = dict.export_file_format
	if dict.has("frame_duration"):
		frame_duration = dict.frame_duration
	else:
		for i in frames.size():
			if i < frame_duration.size():
				continue
			frame_duration.append(1)


func name_changed(value : String) -> void:
	name = value
	global.tabs.set_tab_title(global.tabs.current_tab, name)


func size_changed(value : Vector2) -> void:
	size = value
	if global.selection_rectangle._selected_rect.has_no_area():
		select_all_pixels()


func frames_changed(value : Array) -> void:
	frames = value
	remove_cel_buttons()

	for frame_id in global.frame_ids.get_children():
		global.frame_ids.remove_child(frame_id)
		frame_id.queue_free()

	for i in range(layers.size() - 1, -1, -1):
		global.frames_container.add_child(layers[i].frame_container)

	for j in range(frames.size()):
		var label := Label.new()
		label.rect_min_size.x = 36
		label.align = Label.ALIGN_CENTER
		label.text = str(j + 1)
		global.frame_ids.add_child(label)

		for i in range(layers.size() - 1, -1, -1):
			var cel_button = load("res://addons/pixelorama/src/UI/Timeline/CelButton.tscn").instance()
			cel_button.frame = j
			cel_button.layer = i
			cel_button.get_child(0).texture = frames[j].cels[i].image_texture

			layers[i].frame_container.add_child(cel_button)

	set_timeline_first_and_last_frames()


func layers_changed(value : Array) -> void:
	layers = value
	if global.layers_changed_skip:
		global.layers_changed_skip = false
		return

	for container in global.layers_container.get_children():
		container.queue_free()

	remove_cel_buttons()

	for i in range(layers.size() - 1, -1, -1):
		var layer_container = load("res://addons/pixelorama/src/UI/Timeline/LayerButton.tscn").instance()
		layer_container.i = i
		if layers[i].name == tr("Layer") + " 0":
			layers[i].name = tr("Layer") + " %s" % i

		global.layers_container.add_child(layer_container)
		
#		global.layers_container._enter_tree()
		
		layer_container.label.text = layers[i].name
		layer_container.line_edit.text = layers[i].name

		global.frames_container.add_child(layers[i].frame_container)
		for j in range(frames.size()):
			var cel_button = load("res://addons/pixelorama/src/UI/Timeline/CelButton.tscn").instance()
			cel_button.frame = j
			cel_button.layer = i
			cel_button.get_child(0).texture = frames[j].cels[i].image_texture

			layers[i].frame_container.add_child(cel_button)

	var layer_button = global.layers_container.get_child(global.layers_container.get_child_count() - 1 - current_layer)
	layer_button.pressed = true
	self.current_frame = current_frame # Call frame_changed to update UI
	toggle_layer_buttons_layers()


func remove_cel_buttons() -> void:
	for container in global.frames_container.get_children():
		for button in container.get_children():
			container.remove_child(button)
			button.queue_free()
		global.frames_container.remove_child(container)


func frame_changed(value : int) -> void:
	current_frame = value
	global.current_frame_mark_label.text = "%s/%s" % [str(current_frame + 1), frames.size()]

	for i in frames.size():
		var text_color := Color.white
		if global.theme_type == global.Theme_Types.CARAMEL || global.theme_type == global.Theme_Types.LIGHT:
			text_color = Color.black
		global.frame_ids.get_child(i).add_color_override("font_color", text_color)
		for layer in layers: # De-select all the other frames
			if i < layer.frame_container.get_child_count():
				layer.frame_container.get_child(i).pressed = false

	# Select the new frame
	if current_frame < global.frame_ids.get_child_count():
		global.frame_ids.get_child(current_frame).add_color_override("font_color", global.control.theme.get_color("Selected Color", "Label"))
	if layers and current_frame < layers[current_layer].frame_container.get_child_count():
		layers[current_layer].frame_container.get_child(current_frame).pressed = true

	global.disable_button(global.remove_frame_button, frames.size() == 1)
	global.disable_button(global.move_left_frame_button, frames.size() == 1 or current_frame == 0)
	global.disable_button(global.move_right_frame_button, frames.size() == 1 or current_frame == frames.size() - 1)

	global.canvas.update()
	global.transparent_checker._enter_tree() # To update the rect size


func layer_changed(value : int) -> void:
	current_layer = value
	if current_frame < frames.size():
		global.layer_opacity_slider.value = frames[current_frame].cels[current_layer].opacity * 100
		global.layer_opacity_spinbox.value = frames[current_frame].cels[current_layer].opacity * 100

	for container in global.layers_container.get_children():
		container.pressed = false

	if current_layer < global.layers_container.get_child_count():
		var layer_button = global.layers_container.get_child(global.layers_container.get_child_count() - 1 - current_layer)
		layer_button.pressed = true

	toggle_layer_buttons_current_layer()

	yield(global.get_tree().create_timer(0.01), "timeout")
	self.current_frame = current_frame # Call frame_changed to update UI


func toggle_layer_buttons_layers() -> void:
	if !layers:
		return
	if layers[current_layer].locked:
		global.disable_button(global.remove_layer_button, true)

	if layers.size() == 1:
		global.disable_button(global.remove_layer_button, true)
		global.disable_button(global.move_up_layer_button, true)
		global.disable_button(global.move_down_layer_button, true)
		global.disable_button(global.merge_down_layer_button, true)
	elif !layers[current_layer].locked:
		global.disable_button(global.remove_layer_button, false)


func toggle_layer_buttons_current_layer() -> void:
	if current_layer < layers.size() - 1:
		global.disable_button(global.move_up_layer_button, false)
	else:
		global.disable_button(global.move_up_layer_button, true)

	if current_layer > 0:
		global.disable_button(global.move_down_layer_button, false)
		global.disable_button(global.merge_down_layer_button, false)
	else:
		global.disable_button(global.move_down_layer_button, true)
		global.disable_button(global.merge_down_layer_button, true)

	if current_layer < layers.size():
		if layers[current_layer].locked:
			global.disable_button(global.remove_layer_button, true)
		else:
			if layers.size() > 1:
				global.disable_button(global.remove_layer_button, false)


func animation_tags_changed(value : Array) -> void:
	animation_tags = value
	for child in global.tag_container.get_children():
		child.queue_free()

	for tag in animation_tags:
		var tag_c : Container = load("res://addons/pixelorama/src/UI/Timeline/AnimationTag.tscn").instance()
		global.tag_container.add_child(tag_c)
		var tag_position : int = global.tag_container.get_child_count() - 1
		global.tag_container.move_child(tag_c, tag_position)
		tag_c.get_node("Label").text = tag.name
		tag_c.get_node("Label").modulate = tag.color
		tag_c.get_node("Line2D").default_color = tag.color

		tag_c.rect_position.x = (tag.from - 1) * 39 + tag.from

		var tag_size : int = tag.to - tag.from
		tag_c.rect_min_size.x = (tag_size + 1) * 39
		tag_c.get_node("Line2D").points[2] = Vector2(tag_c.rect_min_size.x, 0)
		tag_c.get_node("Line2D").points[3] = Vector2(tag_c.rect_min_size.x, 32)

	set_timeline_first_and_last_frames()


func set_timeline_first_and_last_frames() -> void:
	# This is useful in case tags get modified DURING the animation is playing
	# otherwise, this code is useless in this context, since these values are being set
	# when the play buttons get pressed anyway
	global.animation_timeline.first_frame = 0
	global.animation_timeline.last_frame = frames.size() - 1
	if global.play_only_tags:
		for tag in animation_tags:
			if current_frame + 1 >= tag.from && current_frame + 1 <= tag.to:
				global.animation_timeline.first_frame = tag.from - 1
				global.animation_timeline.last_frame = min(frames.size() - 1, tag.to - 1)


func has_changed_changed(value : bool) -> void:
	has_changed = value
	if value:
		global.tabs.set_tab_title(global.tabs.current_tab, name + "(*)")
	else:
		global.tabs.set_tab_title(global.tabs.current_tab, name)
