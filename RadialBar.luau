--!strict
-- Workaround for circular progress "bars" in Roblox
-- @ko5i on discord

const RunService = game:GetService("RunService");

const gradientTransparency = NumberSequence.new{
	NumberSequenceKeypoint.new(0, 1);
	NumberSequenceKeypoint.new(.5, 1);
	NumberSequenceKeypoint.new(.501, 0);
	NumberSequenceKeypoint.new(1, 0);
};

type RadialBar = {
	Parent	: Frame;
	Destroy : () -> ();
	base	: ImageLabel;
	alpha	: number;
};

type _RadialBar = {
	Parent	: Frame;
	Destroy : () -> ();
	base	: ImageLabel;
	right	: UIGradient;
	left	: UIGradient;
	alpha	: number;
	prevAlpha : number;
}

local RadialBar = {};
local bars = {} :: {_RadialBar};

function RadialBar.MakeRadio(base:ImageLabel) : RadialBar
	local frame = Instance.new("Frame");
	frame.AnchorPoint = base.AnchorPoint;
	frame.Position = base.Position;
	frame.Size = base.Size;
	frame.BackgroundColor3 = base.BackgroundColor3;
	frame.BackgroundTransparency = base.BackgroundTransparency;
	frame.ZIndex = base.ZIndex;
	Instance.new("UIAspectRatioConstraint", frame);
	frame.Name = base.Name;
	base.Name = "base";
	
	local right = Instance.new("CanvasGroup");
	right.BackgroundTransparency = 1;
	right.Position = UDim2.fromScale(.5, 0);
	right.Size = UDim2.fromScale(.5, 1);
	right.Name = "RightCanvas";
	local left = Instance.new("CanvasGroup");
	left.BackgroundTransparency = 1;
	left.Size = UDim2.fromScale(.5, 1);
	left.Position = UDim2.new();
	right.Name = "LeftCanvas";
	
	local rightImg = base:Clone();
	rightImg.BackgroundTransparency = 1;
	rightImg.AnchorPoint = Vector2.zero;
	rightImg.Size = UDim2.fromScale(2, 1);
	do
		local hasGradient = rightImg:FindFirstChildOfClass("UIGradient");
		if hasGradient then
			hasGradient:Destroy();
		end
		local hasAspect = rightImg:FindFirstChildOfClass("UIAspectRatioConstraint");
		if hasAspect then
			hasAspect:Destroy();
		end
	end
	local leftImg = rightImg:Clone();
	leftImg.Position = UDim2.new();
	rightImg.Position = UDim2.fromScale(-1, 0);
	
	local rightGradient = Instance.new("UIGradient");
	rightGradient.Transparency = gradientTransparency;
	local leftGradient = Instance.new("UIGradient");
	leftGradient.Transparency = gradientTransparency;
	
	rightImg.Parent = right;
	leftImg.Parent = left;
	rightGradient.Parent = rightImg;
	leftGradient.Parent = leftImg;
	right.Parent = frame;
	left.Parent = frame;
	frame.Parent = base.Parent;
	base.Visible = false;
	base.Parent = frame;
	
	local new = {
		Parent = frame;
		base = base;
		right = rightGradient;
		left = leftGradient;
		alpha = 0;
		prevAlpha = -1;
	};
	
	function new.Destroy()
		local find = table.find(bars, new);
		if find then
			table.remove(bars, find);
		end
		frame:Destroy();
	end
	base.Destroying:Connect(new.Destroy);
	
	table.insert(bars, new);
	return new;
end

RunService.PreRender:Connect(function()
	for _, self in ipairs(bars) do
		local prevAlpha = self.prevAlpha;
		local alpha = self.alpha;
		if prevAlpha == alpha then
			continue;
		end
		self.prevAlpha = alpha;
		--------------------------------------------------
		
		local baseRotation = self.base.Rotation;
		self.right.Rotation = math.clamp(alpha*360, 0, 180) - 180 - baseRotation;
		self.left.Rotation = math.clamp(alpha*360-180, 0, 180) - baseRotation;
		self.Parent.Visible = alpha > 0;
	end
end)

return RadialBar;
