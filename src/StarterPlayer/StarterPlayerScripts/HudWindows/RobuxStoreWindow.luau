--!strict
--[[
	RobuxStoreWindow.luau
	Unified left-side Robux Shop modal (`Shop` button on the left HUD column):
	1. Featured Robux Slime Eggs (`GameConfig.ShopEggs`: Enchanted Egg [New!] & Rainbow Egg [LIMITED])
	   with live 3D ViewportFrame slime odds tiles and Robux-only Buy x1 / Buy x3 buttons.
	2. Permanent Game Passes (`GameConfig.Robux.Passes`: x2 Luck, x2 Cash, VIP)
	3. Robux Gem Packs (`GameConfig.Robux.GemPacks`: 100 / 550 / 1,200 / 2,600 Gems)
	4. One-time Free Bonus Slime Gift card (`free_gift`)
	Any Robux item whose ProductId/PassId is 0 shows a disabled "Coming soon (R$X)" button until real IDs are set.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SlimeFactory = require(Shared:WaitForChild("SlimeFactory"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local RobuxStoreWindow = {}

export type RobuxStoreContext = {
	ModalScrim: Frame,
	OnToast: (message: string, color: Color3?) -> (),
	BindShopLabel: (
		label: TextLabel?,
		itemId: string,
		optionIndex: number,
		style: "Row" | "RowWide" | "Option"
	) -> (),
	BuyShopItem: (itemId: string, quantity: (number | string)?) -> (),
}

export type RobuxStoreHandle = {
	Frame: Frame,
	Refresh: (state: any) -> (),
}

function RobuxStoreWindow.Build(parent: Instance, ctx: RobuxStoreContext): RobuxStoreHandle
	local addCorner = UiKit.AddCorner
	local addStroke = UiKit.AddStroke

	local modal = Instance.new("Frame")
	modal.Name = "RobuxStoreModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(650, 445)
	modal.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
	modal.Visible = false
	modal.ZIndex = 10
	modal.Parent = parent
	addCorner(modal, 14)
	addStroke(modal, Color3.fromRGB(15, 18, 24), 3.2, Enum.ApplyStrokeMode.Border)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 54)
	header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	header.Parent = modal
	addCorner(header, 14)
	UiKit.AddGlossGradient(header, Color3.fromRGB(175, 70, 245))
	addStroke(header, Color3.fromRGB(20, 12, 32), 2.2, Enum.ApplyStrokeMode.Border)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(18, 6)
	title.Size = UDim2.fromOffset(320, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "R$ Robux Shop"
	title.Parent = header
	addStroke(title, Color3.fromRGB(20, 10, 30), 2.5)

	UiKit.CreateBevelButton({
		Name = "CloseBtn",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 1),
		Size = UDim2.fromOffset(40, 40),
		Color = Color3.fromRGB(235, 55, 65),
		CornerRadius = 9,
		Text = "X",
		TextSize = 22,
		OnClick = function()
			UiKit.ToggleModalAnimated(modal, ctx.ModalScrim, false)
		end,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(14, 64)
	scroll.Size = UDim2.new(1, -28, 1, -76)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = modal

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 14)
	listLayout.Parent = scroll

	-- ============================================================================
	-- SECTION 1: FEATURED ROBUX SLIME EGGS (Enchanted Egg [New!] & Rainbow Egg [LIMITED])
	-- ============================================================================
	for _, eggDef in GameConfig.ShopEggs do
		local eggCard = Instance.new("Frame")
		eggCard.Name = `EggCard_{eggDef.Id}`
		eggCard.Size = UDim2.new(1, -10, 0, 174)
		eggCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		eggCard.Parent = scroll
		addCorner(eggCard, 12)
		UiKit.AddGlossGradient(eggCard, SlimeFactory.ToColor3(eggDef.AccentColor):Lerp(Color3.fromRGB(32, 26, 52), 0.42))
		addStroke(eggCard, Color3.fromRGB(18, 15, 28), 2.5, Enum.ApplyStrokeMode.Border)

		local hdr = Instance.new("TextLabel")
		hdr.Position = UDim2.fromOffset(16, 6)
		hdr.Size = UDim2.new(1, -32, 0, 28)
		hdr.BackgroundTransparency = 1
		hdr.Font = Enum.Font.FredokaOne
		hdr.TextSize = 24
		hdr.TextColor3 = Color3.fromRGB(255, 235, 95)
		hdr.Text = `{eggDef.Name}  [{eggDef.Tag}] — ROBUX EXCLUSIVE`
		hdr.Parent = eggCard
		addStroke(hdr, Color3.fromRGB(18, 15, 25), 2.2)

		local oddsRow = Instance.new("Frame")
		oddsRow.Position = UDim2.fromOffset(14, 38)
		oddsRow.Size = UDim2.new(1, -28, 0, 76)
		oddsRow.BackgroundTransparency = 1
		oddsRow.Parent = eggCard

		local oddsLayout = Instance.new("UIListLayout")
		oddsLayout.FillDirection = Enum.FillDirection.Horizontal
		oddsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		oddsLayout.Padding = UDim.new(0, 8)
		oddsLayout.Parent = oddsRow

		for _, item in eggDef.Items do
			local sDef = GameConfig.SlimesById[item.SlimeId] or GameConfig.Slimes[1]
			local tile = Instance.new("Frame")
			tile.Size = UDim2.fromOffset(88, 74)
			tile.BackgroundColor3 = SlimeFactory.GetRarityColor(sDef.Rarity):Lerp(Color3.fromRGB(25, 28, 38), 0.35)
			tile.Parent = oddsRow
			addCorner(tile, 9)
			addStroke(tile, Color3.fromRGB(15, 18, 25), 2, Enum.ApplyStrokeMode.Border)

			local vpHolder = Instance.new("Frame")
			vpHolder.AnchorPoint = Vector2.new(0.5, 0.5)
			vpHolder.Position = UDim2.fromScale(0.5, 0.5)
			vpHolder.Size = UDim2.fromOffset(54, 50)
			vpHolder.BackgroundTransparency = 1
			vpHolder.Parent = tile
			UiKit.CreateSlimeViewport(vpHolder, item.SlimeId, item.Mutation, false)

			local pct = Instance.new("TextLabel")
			pct.Size = UDim2.new(1, 0, 0, 18)
			pct.BackgroundTransparency = 1
			pct.Font = Enum.Font.FredokaOne
			pct.TextSize = 15
			pct.TextColor3 = Color3.fromRGB(255, 255, 255)
			pct.Text = `{item.ChancePercent}%`
			pct.ZIndex = 3
			pct.Parent = tile
			addStroke(pct, Color3.fromRGB(15, 18, 25), 1.6)

			local inc = Instance.new("TextLabel")
			inc.AnchorPoint = Vector2.new(0.5, 1)
			inc.Position = UDim2.new(0.5, 0, 1, -2)
			inc.Size = UDim2.new(1, -4, 0, 16)
			inc.BackgroundTransparency = 1
			inc.Font = Enum.Font.FredokaOne
			inc.TextSize = 13
			inc.TextColor3 = Color3.fromRGB(115, 255, 130)
			inc.Text = item.BonusLabel
			inc.ZIndex = 3
			inc.Parent = tile
			addStroke(inc, Color3.fromRGB(15, 18, 25), 1.5)
		end

		local eggCopy = eggDef
		local _, _, buy1Lbl = UiKit.CreateBevelButton({
			Name = "Buy1RobuxBtn",
			Parent = eggCard,
			Position = UDim2.new(0.5, -210, 1, -44),
			Size = UDim2.fromOffset(196, 36),
			Color = if eggDef.Buy1ProductId > 0 then Color3.fromRGB(85, 235, 75) else Color3.fromRGB(72, 78, 92),
			CornerRadius = 9,
			Text = if eggDef.Buy1ProductId > 0
				then `Buy x1 (R$ {eggDef.Buy1Robux})`
				else `Buy x1 • R$ {eggDef.Buy1Robux} (Soon)`,
			TextSize = 16,
			OnClick = function()
				if eggCopy.Buy1ProductId <= 0 then
					ctx.OnToast(`{eggCopy.Name} (x1 — R${eggCopy.Buy1Robux}) is coming soon!`, Color3.fromRGB(255, 215, 85))
					return
				end
				MarketplaceService:PromptProductPurchase(localPlayer, eggCopy.Buy1ProductId)
			end,
		})
		buy1Lbl.TextTransparency = if eggDef.Buy1ProductId > 0 then 0 else 0.15

		local _, _, buy3Lbl = UiKit.CreateBevelButton({
			Name = "Buy3RobuxBtn",
			Parent = eggCard,
			Position = UDim2.new(0.5, 14, 1, -44),
			Size = UDim2.fromOffset(196, 36),
			Color = if eggDef.Buy3ProductId > 0 then Color3.fromRGB(65, 215, 110) else Color3.fromRGB(72, 78, 92),
			CornerRadius = 9,
			Text = if eggDef.Buy3ProductId > 0
				then `Buy x3 (R$ {eggDef.Buy3Robux})`
				else `Buy x3 • R$ {eggDef.Buy3Robux} (Soon)`,
			TextSize = 16,
			OnClick = function()
				if eggCopy.Buy3ProductId <= 0 then
					ctx.OnToast(`{eggCopy.Name} (x3 — R${eggCopy.Buy3Robux}) is coming soon!`, Color3.fromRGB(255, 215, 85))
					return
				end
				MarketplaceService:PromptProductPurchase(localPlayer, eggCopy.Buy3ProductId)
			end,
		})
		buy3Lbl.TextTransparency = if eggDef.Buy3ProductId > 0 then 0 else 0.15
	end

	-- ============================================================================
	-- SECTION 2: GAME PASSES (x2 Luck, x2 Cash, VIP)
	-- ============================================================================
	local passesCard = Instance.new("Frame")
	passesCard.Name = "PassesSection"
	passesCard.Size = UDim2.new(1, -10, 0, 50 + #GameConfig.Robux.Passes * 62)
	passesCard.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
	passesCard.Parent = scroll
	addCorner(passesCard, 12)
	addStroke(passesCard, Color3.fromRGB(16, 18, 24), 2.2, Enum.ApplyStrokeMode.Border)

	local passesTitle = Instance.new("TextLabel")
	passesTitle.Position = UDim2.fromOffset(14, 8)
	passesTitle.Size = UDim2.new(1, -28, 0, 32)
	passesTitle.BackgroundTransparency = 1
	passesTitle.Font = Enum.Font.FredokaOne
	passesTitle.TextSize = 22
	passesTitle.TextXAlignment = Enum.TextXAlignment.Left
	passesTitle.TextColor3 = Color3.fromRGB(255, 225, 85)
	passesTitle.Text = "⭐ GAME PASSES (PERMANENT)"
	passesTitle.Parent = passesCard
	addStroke(passesTitle, Color3.fromRGB(15, 18, 25), 2)

	type PassButtonUI = {
		Pass: GameConfig.RobuxPassDef,
		Face: Frame,
		Label: TextLabel,
	}
	local passButtons: { PassButtonUI } = {}

	for i, pass in GameConfig.Robux.Passes do
		local row = Instance.new("Frame")
		row.Name = `PassRow_{pass.Id}`
		row.Position = UDim2.fromOffset(12, 46 + (i - 1) * 60)
		row.Size = UDim2.new(1, -24, 0, 52)
		row.BackgroundColor3 = SlimeFactory.ToColor3(pass.Color):Lerp(Color3.fromRGB(24, 28, 38), 0.58)
		row.Parent = passesCard
		addCorner(row, 10)
		addStroke(row, Color3.fromRGB(16, 18, 24), 1.8, Enum.ApplyStrokeMode.Border)

		local pName = Instance.new("TextLabel")
		pName.Position = UDim2.fromOffset(12, 4)
		pName.Size = UDim2.new(1, -210, 0, 24)
		pName.BackgroundTransparency = 1
		pName.Font = Enum.Font.FredokaOne
		pName.TextSize = 20
		pName.TextXAlignment = Enum.TextXAlignment.Left
		pName.TextColor3 = Color3.fromRGB(255, 255, 255)
		pName.Text = `{pass.Icon} {pass.Name}`
		pName.Parent = row
		addStroke(pName, Color3.fromRGB(15, 18, 25), 1.8)

		local pSub = Instance.new("TextLabel")
		pSub.Position = UDim2.fromOffset(12, 26)
		pSub.Size = UDim2.new(1, -210, 0, 20)
		pSub.BackgroundTransparency = 1
		pSub.Font = Enum.Font.FredokaOne
		pSub.TextSize = 15
		pSub.TextXAlignment = Enum.TextXAlignment.Left
		pSub.TextColor3 = Color3.fromRGB(205, 220, 240)
		pSub.Text = pass.Description
		pSub.Parent = row
		addStroke(pSub, Color3.fromRGB(15, 18, 25), 1.5)

		local passCopy = pass
		local _, btnFace, btnLbl = UiKit.CreateBevelButton({
			Name = `BuyPass_{pass.Id}`,
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 1),
			Size = UDim2.fromOffset(178, 38),
			Color = if pass.PassId > 0 then Color3.fromRGB(65, 215, 105) else Color3.fromRGB(72, 78, 92),
			CornerRadius = 9,
			Text = if pass.PassId > 0 then `R$ {pass.RobuxPrice}` else `Coming soon (R${pass.RobuxPrice})`,
			TextSize = 16,
			OnClick = function()
				if passCopy.PassId <= 0 then
					ctx.OnToast(`{passCopy.Name} is coming soon!`, Color3.fromRGB(255, 215, 85))
					return
				end
				MarketplaceService:PromptGamePassPurchase(localPlayer, passCopy.PassId)
			end,
		})

		passButtons[i] = {
			Pass = pass,
			Face = btnFace,
			Label = btnLbl,
		}
	end

	-- ============================================================================
	-- SECTION 3: GEM PACKS (100 / 550 / 1,200 / 2,600 Gems)
	-- ============================================================================
	local packsCard = Instance.new("Frame")
	packsCard.Name = "GemPacksSection"
	packsCard.Size = UDim2.new(1, -10, 0, 50 + #GameConfig.Robux.GemPacks * 60)
	packsCard.BackgroundColor3 = Color3.fromRGB(28, 36, 52)
	packsCard.Parent = scroll
	addCorner(packsCard, 12)
	addStroke(packsCard, Color3.fromRGB(16, 18, 24), 2.2, Enum.ApplyStrokeMode.Border)

	local packsTitle = Instance.new("TextLabel")
	packsTitle.Position = UDim2.fromOffset(14, 8)
	packsTitle.Size = UDim2.new(1, -28, 0, 32)
	packsTitle.BackgroundTransparency = 1
	packsTitle.Font = Enum.Font.FredokaOne
	packsTitle.TextSize = 22
	packsTitle.TextXAlignment = Enum.TextXAlignment.Left
	packsTitle.TextColor3 = Color3.fromRGB(120, 210, 255)
	packsTitle.Text = "💎 ROBUX GEM PACKS"
	packsTitle.Parent = packsCard
	addStroke(packsTitle, Color3.fromRGB(15, 18, 25), 2)

	for i, pack in GameConfig.Robux.GemPacks do
		local row = Instance.new("Frame")
		row.Name = `PackRow_{pack.Id}`
		row.Position = UDim2.fromOffset(12, 46 + (i - 1) * 58)
		row.Size = UDim2.new(1, -24, 0, 50)
		row.BackgroundColor3 = Color3.fromRGB(38, 48, 68)
		row.Parent = packsCard
		addCorner(row, 10)
		addStroke(row, Color3.fromRGB(16, 18, 24), 1.8, Enum.ApplyStrokeMode.Border)

		local tagSuffix = if pack.BonusTag and pack.BonusTag ~= "" then `  [{pack.BonusTag}]` else ""
		local pTitle = Instance.new("TextLabel")
		pTitle.Position = UDim2.fromOffset(12, 4)
		pTitle.Size = UDim2.new(1, -210, 0, 22)
		pTitle.BackgroundTransparency = 1
		pTitle.Font = Enum.Font.FredokaOne
		pTitle.TextSize = 19
		pTitle.TextXAlignment = Enum.TextXAlignment.Left
		pTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		pTitle.Text = `{pack.Icon} {pack.Name}{tagSuffix}`
		pTitle.Parent = row
		addStroke(pTitle, Color3.fromRGB(15, 18, 25), 1.8)

		local pGems = Instance.new("TextLabel")
		pGems.Position = UDim2.fromOffset(12, 26)
		pGems.Size = UDim2.new(1, -210, 0, 20)
		pGems.BackgroundTransparency = 1
		pGems.Font = Enum.Font.FredokaOne
		pGems.TextSize = 16
		pGems.TextXAlignment = Enum.TextXAlignment.Left
		pGems.TextColor3 = Color3.fromRGB(125, 220, 255)
		pGems.Text = `+{GameConfig.FormatNumber(pack.Gems)} Gems`
		pGems.Parent = row
		addStroke(pGems, Color3.fromRGB(15, 18, 25), 1.5)

		local packCopy = pack
		local _, _, btnLbl = UiKit.CreateBevelButton({
			Name = `BuyPack_{pack.Id}`,
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 1),
			Size = UDim2.fromOffset(178, 36),
			Color = if pack.ProductId > 0 then Color3.fromRGB(65, 215, 105) else Color3.fromRGB(72, 78, 92),
			CornerRadius = 9,
			Text = if pack.ProductId > 0 then `R$ {pack.RobuxPrice}` else `Coming soon (R${pack.RobuxPrice})`,
			TextSize = 16,
			OnClick = function()
				if packCopy.ProductId <= 0 then
					ctx.OnToast(`{packCopy.Name} is coming soon!`, Color3.fromRGB(255, 215, 85))
					return
				end
				MarketplaceService:PromptProductPurchase(localPlayer, packCopy.ProductId)
			end,
		})
		btnLbl.TextTransparency = if pack.ProductId > 0 then 0 else 0.25
	end

	-- ============================================================================
	-- SECTION 4: FREE BONUS SLIME GIFT CARD
	-- ============================================================================
	local freeGiftCard = Instance.new("Frame")
	freeGiftCard.Name = "FreeGiftCard"
	freeGiftCard.Size = UDim2.new(1, -10, 0, 108)
	freeGiftCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	freeGiftCard.Parent = scroll
	addCorner(freeGiftCard, 12)
	UiKit.AddGlossGradient(freeGiftCard, Color3.fromRGB(65, 175, 245))
	addStroke(freeGiftCard, Color3.fromRGB(18, 22, 32), 2.5, Enum.ApplyStrokeMode.Border)

	local freeVpHolder = Instance.new("Frame")
	freeVpHolder.Position = UDim2.fromOffset(12, 10)
	freeVpHolder.Size = UDim2.fromOffset(86, 86)
	freeVpHolder.BackgroundColor3 = Color3.fromRGB(35, 95, 155)
	freeVpHolder.Parent = freeGiftCard
	addCorner(freeVpHolder, 10)
	addStroke(freeVpHolder, Color3.fromRGB(15, 20, 30), 2, Enum.ApplyStrokeMode.Border)
	UiKit.CreateSlimeViewport(freeVpHolder, GameConfig.FreeGift.SlimeId, GameConfig.FreeGift.Mutation, false)

	local freeGiftTitle = Instance.new("TextLabel")
	freeGiftTitle.Position = UDim2.fromOffset(112, 16)
	freeGiftTitle.Size = UDim2.new(1, -290, 0, 74)
	freeGiftTitle.BackgroundTransparency = 1
	freeGiftTitle.Font = Enum.Font.FredokaOne
	freeGiftTitle.TextSize = 22
	freeGiftTitle.TextWrapped = true
	freeGiftTitle.TextXAlignment = Enum.TextXAlignment.Left
	freeGiftTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	freeGiftTitle.Text = "Free Slime!\nClaim your free Emerald Sakura ($18/s)"
	freeGiftTitle.Parent = freeGiftCard
	addStroke(freeGiftTitle, Color3.fromRGB(15, 20, 30), 2.2)

	local _, _, freeGiftClaimLbl = UiKit.CreateBevelButton({
		Name = "FreeClaimBtn",
		Parent = freeGiftCard,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 2),
		Size = UDim2.fromOffset(152, 48),
		Color = Color3.fromRGB(95, 245, 75),
		CornerRadius = 11,
		Text = "CLAIM!",
		TextSize = 24,
		OnClick = function()
			ctx.BuyShopItem("free_gift", 1)
		end,
	})
	ctx.BindShopLabel(freeGiftClaimLbl, "free_gift", 1, "Option")

	local function refresh(state: any)
		local ownedPasses = if type(state.OwnedPasses) == "table" then state.OwnedPasses else {}
		for _, pb in passButtons do
			if ownedPasses[pb.Pass.Id] == true then
				pb.Face.BackgroundColor3 = Color3.fromRGB(55, 155, 235)
				pb.Label.Text = "OWNED ✓"
				pb.Label.TextTransparency = 0
			elseif pb.Pass.PassId <= 0 then
				pb.Face.BackgroundColor3 = Color3.fromRGB(72, 78, 92)
				pb.Label.Text = `Coming soon (R${pb.Pass.RobuxPrice})`
				pb.Label.TextTransparency = 0.25
			else
				pb.Face.BackgroundColor3 = Color3.fromRGB(65, 215, 105)
				pb.Label.Text = `R$ {pb.Pass.RobuxPrice}`
				pb.Label.TextTransparency = 0
			end
		end
	end

	return {
		Frame = modal,
		Refresh = refresh,
	}
end

return RobuxStoreWindow
