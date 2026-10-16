local M = {}

local hovered_info = ya.sync(function()
	local hovered = cx.active.current.hovered
	if not hovered then
		return nil
	end

	return {
		name = hovered.name,
		path = tostring(hovered.url.path),
		is_dir = hovered.cha.is_dir,
		size = hovered:size(),
		mtime = hovered.cha.mtime,
		btime = hovered.cha.btime,
		perm = hovered.cha:perm(),
	}
end)

local function trim(value)
	if value == nil then
		return nil
	end
	return value:match("^%s*(.-)%s*$")
end

local function run_command(program, args)
	local child = Command(program):arg(args):stdout(Command.PIPED):spawn()
	if not child then
		return nil
	end

	local output = child:wait_with_output()
	if output and output.status.success and output.stdout then
		return output.stdout
	end

	return nil
end

local function add_line(lines, label, value)
	value = trim(value)
	if value and value ~= "" and value ~= "unknown" and value ~= "Undefined" then
		table.insert(lines, label .. ": " .. value)
	end
end

local function format_time(timestamp)
	if not timestamp then
		return nil
	end
	timestamp = tonumber(timestamp)
	if not timestamp then
		return nil
	end
	return os.date("%Y-%m-%d %H:%M", math.floor(timestamp))
end

local function format_size(bytes)
	if not bytes then
		return "Unknown"
	end
	local units = { "B", "KB", "MB", "GB", "TB" }
	local i = 1
	while bytes >= 1024 and i < #units do
		bytes = bytes / 1024
		i = i + 1
	end
	return string.format("%.2f %s", bytes, units[i])
end

local function parse_key_value_lines(output)
	local values = {}
	for line in output:gmatch("[^\r\n]+") do
		local key, value = line:match("^([^:]+):%s*(.-)%s*$")
		if key and value and value ~= "" then
			values[key] = value
		end
	end
	return values
end

local function xml_text(xml, name)
	if not xml then
		return nil
	end

	local value = xml:match("<[%w_]+:" .. name .. "[^>]*>(.-)</[%w_]+:" .. name .. ">")
		or xml:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")

	if not value then
		return nil
	end

	return trim(
		value
			:gsub("&lt;", "<")
			:gsub("&gt;", ">")
			:gsub("&quot;", '"')
			:gsub("&apos;", "'")
			:gsub("&amp;", "&")
	)
end

local function xml_attr(xml, tag, attr)
	if not xml then
		return nil
	end

	local attrs = xml:match("<[%w_]+:" .. tag .. "([^>]*)/?>")
		or xml:match("<" .. tag .. "([^>]*)/?>")
	if not attrs then
		return nil
	end

	return trim(attrs:match(attr .. '="([^"]+)"'))
end

local function get_file_kind(path)
	return trim(run_command("file", { "--brief", path }))
end

local function get_mime_type(path)
	return trim(run_command("file", { "--brief", "--mime-type", path }))
end

local function get_image_metadata(path)
	local output = run_command("identify", { "-ping", "-format", "%m\n%wx%h\n%[colorspace]\n%z\n%n", path })
	if not output then
		return nil
	end

	local values = {}
	for line in output:gmatch("[^\r\n]+") do
		values[#values + 1] = trim(line)
	end

	local frames = tonumber(values[5])
	return {
		format = values[1],
		resolution = values[2],
		color_space = values[3],
		depth = values[4] and (values[4] .. " bit") or nil,
		frames = frames and frames > 1 and tostring(frames) or nil,
	}
end

local function get_pdf_metadata(path)
	local output = run_command("pdfinfo", { path })
	if not output then
		local pages = trim(run_command("qpdf", { "--show-npages", path }))
		return pages and { pages = pages } or nil
	end

	local values = parse_key_value_lines(output)
	if not values["Pages"] then
		values["Pages"] = trim(run_command("qpdf", { "--show-npages", path }))
	end

	return {
		pages = values["Pages"],
		page_size = values["Page size"],
		title = values["Title"],
		author = values["Author"],
		creator = values["Creator"],
		producer = values["Producer"],
		encrypted = values["Encrypted"],
		version = values["PDF version"],
	}
end

local function get_docx_metadata(path)
	local core = run_command("unzip", { "-p", path, "docProps/core.xml" })
	local app = run_command("unzip", { "-p", path, "docProps/app.xml" })
	if not core and not app then
		return nil
	end

	return {
		title = xml_text(core, "title"),
		subject = xml_text(core, "subject"),
		author = xml_text(core, "creator"),
		application = xml_text(app, "Application"),
		pages = xml_text(app, "Pages"),
		words = xml_text(app, "Words"),
		characters = xml_text(app, "Characters"),
	}
end

local function get_odt_metadata(path)
	local meta = run_command("unzip", { "-p", path, "meta.xml" })
	if not meta then
		return nil
	end

	return {
		title = xml_text(meta, "title"),
		subject = xml_text(meta, "subject"),
		author = xml_text(meta, "creator") or xml_text(meta, "initial-creator"),
		pages = xml_attr(meta, "document-statistic", "meta:page-count") or xml_attr(meta, "document-statistic", "page-count"),
		words = xml_attr(meta, "document-statistic", "meta:word-count") or xml_attr(meta, "document-statistic", "word-count"),
		images = xml_attr(meta, "document-statistic", "meta:image-count") or xml_attr(meta, "document-statistic", "image-count"),
	}
end

function M:entry()
	local hovered = hovered_info()
	if not hovered then
		ya.notify({ title = "File Info", content = "No file selected", timeout = 3.0, level = "warn" })
		return
	end

	local name = hovered.name
	local path = hovered.path
	local size_str = format_size(hovered.size)
	local lines = {}
	local ext = name:match("%.([^%.]+)$")
	ext = ext and ext:lower() or ""

	add_line(lines, "Name", name)
	add_line(lines, "Size", size_str)
	add_line(lines, "Modified", format_time(hovered.mtime))
	add_line(lines, "Created", format_time(hovered.btime))
	add_line(lines, "Permissions", hovered.perm)

	if hovered.is_dir then
		add_line(lines, "Type", "Directory")
	else
		add_line(lines, "Type", get_file_kind(path))
		add_line(lines, "MIME", get_mime_type(path))

		if ext == "pdf" then
			local pdf = get_pdf_metadata(path)
			if pdf then
				add_line(lines, "Pages", pdf.pages)
				add_line(lines, "Page Size", pdf.page_size)
				add_line(lines, "Title", pdf.title)
				add_line(lines, "Author", pdf.author)
				add_line(lines, "Encrypted", pdf.encrypted)
				add_line(lines, "PDF Version", pdf.version)
			end
		elseif ext:match("^(png|jpe?g|webp|gif|bmp|tiff|avif|heic)$") then
			local image = get_image_metadata(path)
			if image then
				add_line(lines, "Format", image.format)
				add_line(lines, "Resolution", image.resolution)
				add_line(lines, "Color Space", image.color_space)
				add_line(lines, "Depth", image.depth)
				add_line(lines, "Frames", image.frames)
			end
		elseif ext == "docx" then
			local docx = get_docx_metadata(path)
			if docx then
				add_line(lines, "Title", docx.title)
				add_line(lines, "Subject", docx.subject)
				add_line(lines, "Author", docx.author)
				add_line(lines, "Pages", docx.pages)
				add_line(lines, "Words", docx.words)
				add_line(lines, "Characters", docx.characters)
				add_line(lines, "Application", docx.application)
			end
		elseif ext == "odt" then
			local odt = get_odt_metadata(path)
			if odt then
				add_line(lines, "Title", odt.title)
				add_line(lines, "Subject", odt.subject)
				add_line(lines, "Author", odt.author)
				add_line(lines, "Pages", odt.pages)
				add_line(lines, "Words", odt.words)
				add_line(lines, "Images", odt.images)
			end
		elseif ext == "doc" then
			add_line(lines, "Document", "Legacy Word file")
		end
	end

	ya.confirm({
		pos = { "center", w = 72, h = math.min(math.max(#lines + 6, 8), 24) },
		title = "File Information",
		body = table.concat(lines, "\n") .. "\n\nPress the shortcut again or Esc to close.",
	})
end

return M
