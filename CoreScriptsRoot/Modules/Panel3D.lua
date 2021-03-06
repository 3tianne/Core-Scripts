--Panel3D: 3D GUI panels for VR
--written by 0xBAADF00D
local PIXELS_PER_STUD = 64
local SETTINGS_DISTANCE = 3.5

local CURSOR_HIDE_TIME = 2
local CURSOR_FADE_TIME = 0.125

local CoreGui = game:GetService('CoreGui')
local RobloxGui = CoreGui:WaitForChild("RobloxGui")

local Panel3D = {}

Panel3D.Panels = {
	Lower = 1,
	Hamburger = 2,
	Settings = 3
}

Panel3D.Orientation = {
	Horizontal = 1,
	Fixed = 2
}

Panel3D.Visibility = {
	BelowAngleThreshold = 1,
	Modal = 2
}

local panelDefaultVectors = {
	[Panel3D.Panels.Lower] = CFrame.Angles(math.rad(-45), 0, 0):vectorToWorldSpace(Vector3.new(0, 0, -5)),
	[Panel3D.Panels.Hamburger] = CFrame.Angles(math.rad(-55), 0, 0):vectorToWorldSpace(Vector3.new(0, 0, -5)),
	[Panel3D.Panels.Settings] = Vector3.new(0, 0, -SETTINGS_DISTANCE)
}
local panelLockThreshold = math.rad(-25)
local panelTransparencyBias = { --tuned values; raise the opacity value to this power
	[Panel3D.Panels.Lower] = 6.5,
	[Panel3D.Panels.Hamburger] = 8,
	[Panel3D.Panels.Settings] = 0
}
local panels = {}

local renderStepName = "Panel3D"

local cursor = Instance.new("ImageLabel")
cursor.Image = "rbxasset://textures/Cursors/Gamepad/Pointer.png"
cursor.Size = UDim2.new(0, 8, 0, 8)
cursor.BackgroundTransparency = 1
cursor.ZIndex = 10

local resetOrientationFlag = false
local currentModalPanel = nil

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local cursorHidden = false
local hasTool = false
local lastMouseMove = tick()

local function OnCharacterAdded(character)
	hasTool = false
	for i, v in ipairs(character:GetChildren()) do
		if v:IsA("Tool") then
			hasTool = true
		end
	end
	character.ChildAdded:connect(function(child)
		if child:IsA("Tool") then
			hasTool = true
			lastMouseMove = tick() --kick the mouse when a tool is equipped
		end
	end)
	character.ChildRemoved:connect(function(child)
		if child:IsA("Tool") then
			hasTool = false
		end
	end)
end
game.Players.LocalPlayer.CharacterAdded:connect(OnCharacterAdded)
if game.Players.LocalPlayer.Character then OnCharacterAdded(game.Players.LocalPlayer.Character) end

local function autoHideCursor(hide)
	if not UserInputService.VREnabled then
		cursorHidden = false
		return
	end
	if hide then
		--don't hide if there's a tool in the character
		local character = game.Players.LocalPlayer.Character
		if character and hasTool then
			return
		end
		cursorHidden = true
		UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
	else
		cursorHidden = false
		UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
	end
end

local function isCursorVisible()
	--if ForceShow, the cursor is definitely visible at all times
	if UserInputService.OverrideMouseIconBehavior == Enum.OverrideMouseIconBehavior.ForceShow then
		return true
	end
	--if ForceHide, the cursor is definitely NOT visible
	if UserInputService.OverrideMouseIconBehavior == Enum.OverrideMouseIconBehavior.ForceHide then
		return false
	end
	--Otherwise, we need to check if the developer set MouseIconEnabled=false
	if UserInputService.MouseIconEnabled and UserInputService.OverrideMouseIconBehavior == Enum.OverrideMouseIconBehavior.None then
		return true
	end
	return false
end

UserInputService.InputChanged:connect(function(inputObj, processed)
	if inputObj.UserInputType == Enum.UserInputType.MouseMovement then
		lastMouseMove = tick()
		autoHideCursor(false)
	end
end)
game:GetService("RunService").Heartbeat:connect(function()
	if isCursorVisible() then
		cursorHidden = false
	end
	if lastMouseMove + CURSOR_HIDE_TIME < tick() and not GuiService.MenuIsOpen and not cursorHidden then
		autoHideCursor(true)
	end
end)

local function createPanel()
	local panelPart = Instance.new("Part")
	panelPart.Transparency = 1
	panelPart.CanCollide = false
	panelPart.Anchored = true
	panelPart.Archivable = false
	panelPart.Size = Vector3.new(1.5, 1.5, 1)
	panelPart.Parent = workspace.CurrentCamera
	local panelGUI = Instance.new("SurfaceGui", CoreGui)
	panelGUI.Name = "GUI"
	panelGUI.Adornee = panelPart
	panelGUI.ToolPunchThroughDistance = 1000
	panelGUI.Active = true
	return panelPart, panelGUI
end

function Panel3D.Get(panelId)
	local panel = panels[panelId]
	if not panel then
		local panelName
		for name, value in pairs(Panel3D.Panels) do
			if value == panelId then
				panelName = name
				break
			end
		end
		if not panelName then
			error("Tried to request an invalid 3D panel")
		end

		local part, gui = createPanel()

		panel = {}
		panel.part = part
		panel.part.Name = "GUI"--("%sPanel3D"):format(panelName)
		panel.gui = gui
		panel.gui.Name = ("%sPanelGUI"):format(panelName)

		panel.vector = panelDefaultVectors[panelId]
		panel.horizontalVector = Vector3.new(panel.vector.x, 0, panel.vector.z).unit
		panel.pitchAngle = math.asin(panel.vector.unit.y)
		panel.verticalRange = math.rad(5)
		panel.horizontalRange = math.rad(5)

		panel.transparencyCallbacks = {}

		panel.OnMouseEnter = nil
		panel.OnMouseLeave = nil

		panel.pixelScale = 1

		panel.visible = true
		panel.visibilityBehavior = Panel3D.Visibility.BelowAngleThreshold

		panel.orientationMode = Panel3D.Orientation.Horizontal
		panel.orientation = nil

		panel.cursorEnabled = true

		function panel:AddTransparencyCallback(callback)
			table.insert(panel.transparencyCallbacks, callback)
		end

		function panel:Resize(width, height, pixelsPerStud)
			pixelsPerStud = pixelsPerStud or PIXELS_PER_STUD
			panel.pixelScale = pixelsPerStud / PIXELS_PER_STUD
			panel.part.Size = Vector3.new(width, height, 1)
			panel.gui.CanvasSize = Vector2.new(pixelsPerStud * width, pixelsPerStud * height)

			local distance = panel.vector.magnitude
			panel.verticalRange = math.atan(panel.part.Size.Y / (2 * distance)) * 2
			panel.horizontalRange = math.atan(panel.part.Size.X / (2 * distance)) * 2
		end

		function panel:ResizePixels(width, height)
			local widthStuds = width / PIXELS_PER_STUD
			local heightStuds = height / PIXELS_PER_STUD
			panel:Resize(widthStuds, heightStuds)
		end

		function panel:SetModal()
			panel.visible = false
			panel.visibilityBehavior = Panel3D.Visibility.Modal
		end

		function panel:SetVisible(visible)
			panel.visible = visible

			if visible and panel.visibilityBehavior == Panel3D.Visibility.Modal then
				currentModalPanel = panel
				if panel.orientationMode == Panel3D.Orientation.Fixed then
					local userHeadCFrame = UserInputService:GetUserCFrame(Enum.UserCFrame.Head)
					panel.orientation = userHeadCFrame * CFrame.new(0, 0, -panel.vector.magnitude) * CFrame.Angles(0, math.pi, 0)
				end
			else
				if currentModalPanel == panel then
					currentModalPanel = nil
				end
			end
		end

		panels[panelId] = panel
	end
	return panel
end

function Panel3D.ResetOrientation()
	resetOrientationFlag = true
end

function Panel3D.GetGUI(panel)
	local panelGUI = panelGUIs[panel]
	if not panelGUI then
		local part = Panel3D.GetPart(panel)
		panelGUI = panelGUIs[panel]
	end
	return panelGUI
end

local zeroVector = Vector3.new(0, 0, 0)
local baseHorizontal = CFrame.new()
local basePosition = Vector3.new()
local currentHoverPanel = nil
local savedMouseBehavior = Enum.MouseBehavior.Default
function Panel3D.OnRenderStep()
	if not UserInputService.VREnabled then
		return
	end
	local cameraRenderCFrame = workspace.CurrentCamera:GetRenderCFrame()
	local userHeadCFrame = UserInputService:GetUserCFrame(Enum.UserCFrame.Head)
	local cameraLook = cameraRenderCFrame.lookVector
	local cameraHorizontalVector = Vector3.new(cameraLook.X, 0, cameraLook.Z).unit
	local cameraPitchAngle = math.asin(cameraLook.Y)

	local position = workspace.CurrentCamera.CFrame.p
	local panelsOrigin = CFrame.new(position) * baseHorizontal * CFrame.new(basePosition)

	local isAboveThreshold = false
	if cameraPitchAngle > panelLockThreshold or resetOrientationFlag then
		isAboveThreshold = true
		baseHorizontal = CFrame.new(zeroVector, cameraHorizontalVector)
		basePosition = userHeadCFrame.p
		resetOrientationFlag = false
	end

	for panelId, panel in pairs(panels) do
		if panel.visibilityBehavior == Panel3D.Visibility.BelowAngleThreshold then
			panel.visible = not isAboveThreshold and not currentModalPanel
		end

		if not panel.visible then
			panel.part.Parent = nil
		else
			panel.part.Parent = workspace.CurrentCamera --TODO: move to new 3D gui space

			local panelCFrame;
			if panel.orientationMode == Panel3D.Orientation.Fixed and panel.orientation then
				panel.part.CFrame = workspace.CurrentCamera.CFrame * panel.orientation
				panelCFrame = panel.part.CFrame
			else
				local panelPosition = panelsOrigin:pointToWorldSpace(panel.vector)
				panelCFrame = CFrame.new(panelPosition, panelsOrigin.p)
				panel.part.CFrame = panelCFrame
			end

			local toPanel = (panelCFrame.p - cameraRenderCFrame.p).unit

			local transparency = panel.visible and 1 - (math.max(0, cameraLook:Dot(toPanel)) ^ panelTransparencyBias[panelId]) or 1
			for _, callback in pairs(panel.transparencyCallbacks) do
				callback(transparency)
			end
		end
	end

	--Render a cursor overlaid onto the panels
	local cframe = cameraRenderCFrame
	local ray = Ray.new(cframe.p, cframe.lookVector * 999)
	local ignoreList = { game.Players.LocalPlayer.Character }
	local part, endpoint = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList)

	local hitPanel = nil
	local hitPanelId = nil
	for panelId, panel in pairs(panels) do
		if part == panel.part then
			hitPanel = panel
			hitPanelId = panelId
		end
	end
	if hitPanel then
		if not currentHoverPanel then
			savedMouseBehavior = UserInputService.MouseBehavior
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		else
			if currentHoverPanel ~= hitPanel then
				if currentHoverPanel.OnMouseLeave then
					currentHoverPanel:OnMouseLeave()
				end
			end
		end
		if hitPanel.OnMouseEnter and currentHoverPanel ~= hitPanel then
			hitPanel:OnMouseEnter()
		end
		
		currentHoverPanel = hitPanel

		UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
		if hitPanel.cursorEnabled then
			cursor.Parent = hitPanel.gui
		else
			cursor.Parent = nil
		end

		local localEndpoint = part:GetRenderCFrame():pointToObjectSpace(endpoint)
		local x = ((localEndpoint.X / part.Size.X) * 1) + 0.5
		local y = ((localEndpoint.Y / part.Size.Y) * 1) + 0.5
		x = 1 - x
		y = 1 - y
		cursor.Size = UDim2.new(0, 8 * hitPanel.pixelScale, 0, 8 * hitPanel.pixelScale)
		cursor.Position = UDim2.new(x, -cursor.AbsoluteSize.x * 0.5, y, -cursor.AbsoluteSize.y * 0.5)

		if hitPanel.visible and not modalPanelIsOpen then
			hitPanel.part.Parent = workspace.CurrentCamera
			for _, callback in pairs(hitPanel.transparencyCallbacks) do
				callback(0)
			end
		end
	else
		if currentHoverPanel then
			UserInputService.MouseBehavior = savedMouseBehavior

			if currentHoverPanel.OnMouseLeave then
				currentHoverPanel:OnMouseLeave()
			end
		end
		currentHoverPanel = false
		cursor.Parent = nil
	end
end

game:GetService("RunService"):BindToRenderStep(renderStepName, Enum.RenderPriority.Last.Value, Panel3D.OnRenderStep)

return Panel3D