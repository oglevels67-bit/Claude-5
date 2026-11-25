-- Claude 5: self-contained chess engine (no Stockfish / Lichess / external APIs, no key system).
-- Faster check detection + piece lists, personality-only styles, Alien/Martian gambits in every style,
-- premove safety re-check, illegal-position guard (no king captures), clock-aware time, game recorder.

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players") local UserInputService =
game:GetService("UserInputService") local TweenService =
game:GetService("TweenService") local RunService =
game:GetService("RunService") local Workspace =
game:GetService("Workspace") local HttpService =
game:GetService("HttpService")

if RunService:IsServer() then return end

local LocalPlayer = Players.LocalPlayer if not LocalPlayer then
error("Twitchys Chess Club Hub must run in a Roblox client environment.") end

local PlayerGui = ( type(rawget(_G, "TWITCHYS_ENV")) == "table" and
typeof(rawget(_G, "TWITCHYS_ENV").GuiParent) == "Instance" and
rawget(_G, "TWITCHYS_ENV").GuiParent ) or
LocalPlayer:FindFirstChildOfClass("PlayerGui") or
LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "Claude5Hub" local AUTO_SCAN_INTERVAL =
0.08 local MATE_SCORE = 1000000 local TOP_MOVE_COUNT = 3 local
BoardTracker = {} BoardTracker.CHESS_CLUB_PLACE_ID = 139394516128799
BoardTracker.chessClubKingCaptureCompatibility = false -- capturing a king is never a legal chess move

local ENGINE_MODES = {
    Instant = { timeLimit = 1.40, softLimit = 0.50, maxDepth = 24, minDepth = 5, easyMinDepth = 6, easyMargin = 140, easyReduce = 2, qchecks = false, singular = false },
    Blitz = { timeLimit = 4.50, softLimit = 1.80, maxDepth = 32, minDepth = 6, easyMinDepth = 8, easyMargin = 180, easyReduce = 1, qchecks = true, singular = true },
    Deep = { timeLimit = 14.00, softLimit = 6.00, maxDepth = 44, minDepth = 7, easyMinDepth = 10, easyMargin = 250, easyReduce = 1, qchecks = true, singular = true },
}

local ENGINE_MODE_ORDER = { "Instant", "Blitz", "Deep" } local
FILE_NAMES = { "a", "b", "c", "d", "e", "f", "g", "h" } local
PROMOTION_PIECES = { "queen", "rook", "bishop", "knight" }

local PIECE_VALUES = { pawn = 100, knight = 320, bishop = 330, rook =
500, queen = 900, king = 20000, }

local PIECE_LETTERS = { pawn = "", knight ="N", bishop = "B", rook =
"R", queen = "Q", king = "K", }

local THEME = { background = Color3.fromRGB(15, 14, 18), header =
Color3.fromRGB(26, 24, 30), surface = Color3.fromRGB(29, 27, 34),
surface2 = Color3.fromRGB(38, 35, 44), surface3 = Color3.fromRGB(52, 48,
60),

    text = Color3.fromRGB(246, 243, 238),
    muted = Color3.fromRGB(168, 161, 153),
    faint = Color3.fromRGB(118, 112, 106),

    accent = Color3.fromRGB(217, 119, 87),
    accent2 = Color3.fromRGB(122, 162, 247),
    success = Color3.fromRGB(74, 198, 136),
    warning = Color3.fromRGB(240, 184, 76),
    danger = Color3.fromRGB(232, 90, 90),

    source = Color3.fromRGB(122, 162, 247),
    destination = Color3.fromRGB(74, 198, 136),
    blackBar = Color3.fromRGB(29, 31, 39),
    whiteBar = Color3.fromRGB(232, 235, 244),

}

for _, oldName in ipairs({ GUI_NAME, "TwitchysChessClubHub", "TwitchysChessClubHubRevamp", "Claude2Hub", "Claude3Hub", "Claude35Hub", "Claude4Hub",
"ChessClubAnalyzerGui", "TwitchysKeySystemOverlay",
"TwitchysHub_Ranked2DArrows", }) do local oldGui =
PlayerGui:FindFirstChild(oldName) if oldGui then oldGui:Destroy() end
end

for _, descendant in ipairs(PlayerGui:GetDescendants()) do if
descendant.Name == "TwitchysHub_2DSourceHighlight" or descendant.Name ==
"TwitchysHub_2DDestinationHighlight" then descendant:Destroy() end end

for _, oldHighlightName in ipairs({ "ChessAI_SourceHighlight",
"ChessAI_DestinationHighlight", "TwitchysChess_SourceHighlight",
"TwitchysChess_DestinationHighlight", "TwitchysHub_SourceHighlight",
"TwitchysHub_DestinationHighlight", "TwitchysHub_ArrowStart",
"TwitchysHub_ArrowEnd", "TwitchysHub_RankedArrowStart1",
"TwitchysHub_RankedArrowEnd1", "TwitchysHub_RankedArrowStart2",
"TwitchysHub_RankedArrowEnd2", "TwitchysHub_RankedArrowStart3",
"TwitchysHub_RankedArrowEnd3", }) do local oldObject =
Workspace:FindFirstChild(oldHighlightName) if oldObject then
oldObject:Destroy() end end

local function inBounds(file, rank) return file >= 1 and file <= 8 and
rank >= 1 and rank <= 8 end

local function opposite(color) return color == "white" and "black" or
"white" end

local function squareName(file, rank) return FILE_NAMES[file] ..
tostring(rank) end

local function squareCoordinates(name) if typeof(name) ~= "string" then
return nil, nil end

    name = string.lower(name)
    if not string.match(name, "^[a-h][1-8]$") then
        return nil, nil
    end

    local file = string.byte(string.sub(name, 1, 1)) - 96
    local rank = tonumber(string.sub(name, 2, 2))
    return file, rank

end

local function horizontalDistance(first, second) return
(Vector2.new(first.X, first.Z) - Vector2.new(second.X,
second.Z)).Magnitude end

local function countDictionary(dictionary) local count = 0 for _ in
pairs(dictionary) do count += 1 end return count end

local function getObjectPosition(object) if not object then return nil
end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        return object:GetPivot().Position
    end

    local part = object:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil

end

local function getVisualPart(object) if not object then return nil end

    if object:IsA("BasePart") then
        return object
    end

    local namedLight = object:FindFirstChild("light", true)
        or object:FindFirstChild("Light", true)

    if namedLight and namedLight:IsA("BasePart") then
        return namedLight
    end

    local largestPart = nil
    local largestArea = 0

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local area = descendant.Size.X * descendant.Size.Z
            if area > largestArea then
                largestArea = area
                largestPart = descendant
            end
        end
    end

    return largestPart

end

local function createEmptyBoard() local board = {} for rank = 1, 8 do
board[rank] = {} end return board end

local function cloneBoard(board) local copy = createEmptyBoard()

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece then
                copy[rank][file] = {
                    color = piece.color,
                    kind = piece.kind,
                    instance = piece.instance,
                }
            end
        end
    end

    return copy

end

local function boardHash(board, colorToMove) local characters =
table.create(65) local index = 1

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if not piece then
                characters[index] = "."
            else
                local letter = string.sub(piece.kind, 1, 1)
                if piece.kind == "knight" then
                    letter = "n"
                end
                if piece.color == "white" then
                    letter = string.upper(letter)
                end
                characters[index] = letter
            end
            index += 1
        end
    end

    characters[index] = colorToMove == "white" and "w" or "b"
    return table.concat(characters)

end

local function normalizeColor(value) if typeof(value) ~= "string" then
return nil end

    value = string.lower(value)
    if value == "white" or value == "w" then
        return "white"
    end
    if value == "black" or value == "b" then
        return "black"
    end
    return nil

end

local function normalizePieceType(value) if typeof(value) ~= "string"
then return nil end

    value = string.lower(value)
    if value == "horse" then
        value = "knight"
    end

    return PIECE_VALUES[value] and value or nil

end

local function parseColorFromName(name) local lowerName =
string.lower(name) if string.find(lowerName, "white", 1, true) then
return "white" end if string.find(lowerName, "black", 1, true) then
return "black" end return nil end

local function parsePieceTypeFromName(name) local lowerName =
string.lower(name)

    if string.find(lowerName, "pawn", 1, true) then
        return "pawn"
    elseif string.find(lowerName, "knight", 1, true)
        or string.find(lowerName, "horse", 1, true) then
        return "knight"
    elseif string.find(lowerName, "bishop", 1, true) then
        return "bishop"
    elseif string.find(lowerName, "rook", 1, true) then
        return "rook"
    elseif string.find(lowerName, "queen", 1, true) then
        return "queen"
    elseif string.find(lowerName, "king", 1, true) then
        return "king"
    end

    return nil

end

local function getPieceInformation(piece) local color = normalizeColor(
piece:GetAttribute("Color") or piece:GetAttribute("Team") or
piece:GetAttribute("PieceColor") )

    local kind = normalizePieceType(
        piece:GetAttribute("PieceType")
            or piece:GetAttribute("Type")
            or piece:GetAttribute("Kind")
    )

    color = color or parseColorFromName(piece.Name)
    kind = kind or parsePieceTypeFromName(piece.Name)

    return color, kind

end

BoardTracker.lastSnapshot = nil BoardTracker.lastPieceHash = nil
BoardTracker.currentPieceHash = nil BoardTracker.currentIdentity = nil
BoardTracker.lastMove = nil BoardTracker.enPassantSquare = nil
BoardTracker.halfmoveClock = 0 BoardTracker.fullmoveNumber = 1
BoardTracker.castling = { K = false, Q = false, k = false, q = false, }
BoardTracker.historyInitialized = false BoardTracker.lastWhiteClock =
nil BoardTracker.lastBlackClock = nil BoardTracker.turnCandidate = nil
BoardTracker.turnCandidateCount = 0 BoardTracker.confirmedTurn = nil
BoardTracker.turnConfidence = 0 BoardTracker.requiredStableScans = 2
BoardTracker.live2DSourceLocked = false
BoardTracker.lastAcceptedDiagnostics = nil

function BoardTracker.isGuiTreeVisible(object) if not object or not
object:IsA("GuiObject") then return false end

    if object.AbsoluteSize.X <= 2 or object.AbsoluteSize.Y <= 2 then
        return false
    end

    local current = object
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("LayerCollector") and not current.Enabled then
            return false
        end
        current = current.Parent
    end

    return true

end

function BoardTracker.get2DBoardNodes() local boardGui =
PlayerGui:FindFirstChild("2DBoard") local main = boardGui and
boardGui:FindFirstChild("Main") local boardFolder = main and
main:FindFirstChild("Board") local piecesFolder = main and
main:FindFirstChild("Pieces") local clocksFolder = main and
main:FindFirstChild("Clocks")

    if not boardGui or not main or not boardFolder or not piecesFolder then
        return nil
    end

    -- The relative GUI positions remain useful even when the 2D board is
    -- temporarily hidden or Roblox loses focus. Avoid AbsolutePosition here.
    return {
        gui = boardGui,
        main = main,
        board = boardFolder,
        pieces = piecesFolder,
        clocks = clocksFolder,
    }

end

function BoardTracker.guiCenter(object) return object.AbsolutePosition +
object.AbsoluteSize * 0.5 end

function BoardTracker.pieceHash(board) return
string.sub(boardHash(board, "white"), 1, 64) end

function BoardTracker.snapshot(board) local snapshot = {} local symbols
= { pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q",
king = "k", }

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece then
                local symbol = symbols[piece.kind]
                if piece.color == "white" then
                    symbol = string.upper(symbol)
                end
                snapshot[squareName(file, rank)] = symbol
            end
        end
    end

    return snapshot

end

function BoardTracker.decodePieceCode(code) if type(code) ~= "string" or
code == "" then return nil, nil end

    local lower = string.lower(code)
    local kinds = {
        p = "pawn",
        n = "knight",
        b = "bishop",
        r = "rook",
        q = "queen",
        k = "king",
    }

    return code == string.upper(code) and "white" or "black", kinds[lower]

end

function BoardTracker.isStartingPosition(board) return
BoardTracker.pieceHash(board) ==
"RNBQKBNRPPPPPPPP…………………………..pppppppprnbqkbnr" end

function BoardTracker.resetHistory(board, identity)
BoardTracker.lastSnapshot = BoardTracker.snapshot(board)
BoardTracker.lastPieceHash = BoardTracker.pieceHash(board)
BoardTracker.currentPieceHash = BoardTracker.lastPieceHash
BoardTracker.currentIdentity = identity BoardTracker.lastMove = nil
BoardTracker.enPassantSquare = nil BoardTracker.halfmoveClock = 0
BoardTracker.fullmoveNumber = 1 BoardTracker.confirmedTurn = nil
BoardTracker.turnConfidence = 0 BoardTracker.turnCandidate = nil
BoardTracker.turnCandidateCount = 0 BoardTracker.lastWhiteClock = nil
BoardTracker.lastBlackClock = nil

    local atStart = BoardTracker.isStartingPosition(board)
    BoardTracker.castling.K = atStart
    BoardTracker.castling.Q = atStart
    BoardTracker.castling.k = atStart
    BoardTracker.castling.q = atStart
    BoardTracker.historyInitialized = true

end

function BoardTracker.castlingString() local result = "" for _, key in
ipairs({ "K", "Q", "k", "q" }) do if BoardTracker.castling[key] then
result ..= key end end return result ~= "" and result or "-" end

function BoardTracker.fenStateKey() return BoardTracker.castlingString()
.. ":" .. (BoardTracker.enPassantSquare or "-") .. ":" ..
tostring(BoardTracker.halfmoveClock or 0) .. ":" ..
tostring(BoardTracker.fullmoveNumber or 1) end

function BoardTracker.matchesCurrentBoard(board) return board and
BoardTracker.currentPieceHash and BoardTracker.pieceHash(board) ==
BoardTracker.currentPieceHash end

function BoardTracker.inferMove(previous, current) local changed = {}
local sources = {} local destinations = {}

    for rank = 1, 8 do
        for file = 1, 8 do
            local square = squareName(file, rank)
            local before = previous[square]
            local after = current[square]
            if before ~= after then
                table.insert(changed, square)
                if before then
                    table.insert(sources, {
                        square = square,
                        code = before,
                        file = file,
                        rank = rank,
                    })
                end
                if after then
                    table.insert(destinations, {
                        square = square,
                        code = after,
                        file = file,
                        rank = rank,
                    })
                end
            end
        end
    end

    -- A normal move changes two squares, en passant changes three, and
    -- castling changes four. More changes means one or more plies were skipped
    -- (usually because of lag or very fast play), so do not invent a move.
    if #changed == 0 or #changed > 4 then
        return nil
    end

    local castlePatterns = {
        { color = "white", king = "K", rook = "R", from = "e1", to = "g1", rookFrom = "h1", rookTo = "f1", castle = "king" },
        { color = "white", king = "K", rook = "R", from = "e1", to = "c1", rookFrom = "a1", rookTo = "d1", castle = "queen" },
        { color = "black", king = "k", rook = "r", from = "e8", to = "g8", rookFrom = "h8", rookTo = "f8", castle = "king" },
        { color = "black", king = "k", rook = "r", from = "e8", to = "c8", rookFrom = "a8", rookTo = "d8", castle = "queen" },
    }

    if #changed == 4 then
        for _, pattern in ipairs(castlePatterns) do
            if previous[pattern.from] == pattern.king
            and previous[pattern.rookFrom] == pattern.rook
            and current[pattern.to] == pattern.king
            and current[pattern.rookTo] == pattern.rook
            and not current[pattern.from]
            and not current[pattern.rookFrom] then
            local fromFile, fromRank = squareCoordinates(pattern.from)
            local toFile, toRank = squareCoordinates(pattern.to)
                return {
                    fromSquare = pattern.from,
                    toSquare = pattern.to,
                    fromFile = fromFile,
                    fromRank = fromRank,
                    toFile = toFile,
                    toRank = toRank,
                    color = pattern.color,
                    kind = "king",
                    castle = pattern.castle,
                    capture = false,
                }
            end
        end
        return nil
    end

    if #changed ~= 2 and #changed ~= 3 then
        return nil
    end

    local best = nil
    local bestScore = math.huge

    for _, source in ipairs(sources) do
        local sourceColor, sourceKind = BoardTracker.decodePieceCode(source.code)
        for _, destination in ipairs(destinations) do
            local destinationColor, destinationKind = BoardTracker.decodePieceCode(destination.code)
            local sameIdentity = sourceColor == destinationColor
                and (sourceKind == destinationKind
                    or (sourceKind == "pawn" and destinationKind ~= "pawn"))

            if sameIdentity and source.square ~= destination.square then
                local fileDistance = math.abs(destination.file - source.file)
                local rankDistance = math.abs(destination.rank - source.rank)
                local score = fileDistance + rankDistance

                if current[source.square] then
                    score += 20
                end
                if sourceKind == "king" and fileDistance > 2 then
                    score += 50
                end

                if score < bestScore then
                    bestScore = score
                    best = {
                        fromSquare = source.square,
                        toSquare = destination.square,
                        fromFile = source.file,
                        fromRank = source.rank,
                        toFile = destination.file,
                        toRank = destination.rank,
                        color = sourceColor,
                        kind = sourceKind,
                        promotion = sourceKind == "pawn"
                            and destinationKind ~= "pawn"
                            and destinationKind
                            or nil,
                        capture = previous[destination.square] ~= nil,
                    }
                end
            end
        end
    end

    if best and best.kind == "pawn" and not best.capture
        and math.abs(best.toFile - best.fromFile) == 1 then
        for _, source in ipairs(sources) do
            if source.square ~= best.fromSquare then
                local color, kind = BoardTracker.decodePieceCode(source.code)
                if kind == "pawn" and color ~= best.color
                    and source.file == best.toFile
                    and source.rank == best.fromRank
                    and not current[source.square] then
                    best.capture = true
                    best.enPassant = true
                    best.capturedSquare = source.square
                    break
                end
            end
        end
    end

    best = best or nil
    if best then
        best.changedSquares = changed
    end
    return best

end

function BoardTracker.updateCastlingRights(move, previous) if not move
then return end

    if move.kind == "king" then
        if move.color == "white" then
            BoardTracker.castling.K = false
            BoardTracker.castling.Q = false
        else
            BoardTracker.castling.k = false
            BoardTracker.castling.q = false
        end
    elseif move.kind == "rook" then
        if move.fromSquare == "h1" then
            BoardTracker.castling.K = false
        elseif move.fromSquare == "a1" then
            BoardTracker.castling.Q = false
        elseif move.fromSquare == "h8" then
            BoardTracker.castling.k = false
        elseif move.fromSquare == "a8" then
            BoardTracker.castling.q = false
        end
    end

    local capturedCode = previous[move.toSquare]
    if capturedCode == "R" then
        if move.toSquare == "h1" then
            BoardTracker.castling.K = false
        elseif move.toSquare == "a1" then
            BoardTracker.castling.Q = false
        end
    elseif capturedCode == "r" then
        if move.toSquare == "h8" then
            BoardTracker.castling.k = false
        elseif move.toSquare == "a8" then
            BoardTracker.castling.q = false
        end
    end

end

function BoardTracker.reconcileCastlingRights(snapshot) if
snapshot["e1"] ~= "K" then BoardTracker.castling.K = false
BoardTracker.castling.Q = false end if snapshot["h1"] ~= "R" then
BoardTracker.castling.K = false end if snapshot["a1"] ~= "R" then
BoardTracker.castling.Q = false end

    if snapshot["e8"] ~= "k" then
        BoardTracker.castling.k = false
        BoardTracker.castling.q = false
    end
    if snapshot["h8"] ~= "r" then
        BoardTracker.castling.k = false
    end
    if snapshot["a8"] ~= "r" then
        BoardTracker.castling.q = false
    end

end

function BoardTracker.observeBoard(board, turnHint, identity) if not
board then return nil end

    local currentHash = BoardTracker.pieceHash(board)
    local currentSnapshot = BoardTracker.snapshot(board)

    if not BoardTracker.historyInitialized
        or (identity and BoardTracker.currentIdentity
            and identity ~= BoardTracker.currentIdentity) then
        BoardTracker.resetHistory(board, identity)
        if turnHint then
            BoardTracker.confirmedTurn = turnHint
            BoardTracker.turnConfidence = 2
        end
        return nil
    end

    if BoardTracker.isStartingPosition(board)
        and BoardTracker.lastPieceHash
        and BoardTracker.lastPieceHash ~= currentHash then
        BoardTracker.resetHistory(board, identity)
        BoardTracker.confirmedTurn = "white"
        BoardTracker.turnConfidence = 2
        return nil
    end

    BoardTracker.currentIdentity = identity or BoardTracker.currentIdentity
    BoardTracker.currentPieceHash = currentHash

    if currentHash == BoardTracker.lastPieceHash then
        if turnHint then
            BoardTracker.confirmedTurn = turnHint
        end
        return nil
    end

    local move = BoardTracker.inferMove(BoardTracker.lastSnapshot, currentSnapshot)
    if move then
        BoardTracker.updateCastlingRights(move, BoardTracker.lastSnapshot)
        BoardTracker.enPassantSquare = nil

        if move.kind == "pawn"
            and math.abs(move.toRank - move.fromRank) == 2 then
            BoardTracker.enPassantSquare = squareName(
                move.fromFile,
                math.floor((move.fromRank + move.toRank) / 2)
            )
        end

        if move.kind == "pawn" or move.capture then
            BoardTracker.halfmoveClock = 0
        else
            BoardTracker.halfmoveClock += 1
        end

        if move.color == "black" then
            BoardTracker.fullmoveNumber += 1
        end

        BoardTracker.lastMove = move
        BoardTracker.confirmedTurn = opposite(move.color)
        BoardTracker.turnConfidence = 2
        BoardTracker.turnCandidate = BoardTracker.confirmedTurn
        BoardTracker.turnCandidateCount = 2
    else
        -- The live board changed by more than one recognizable ply. Keep the
        -- current piece placement, but do not fabricate move history from it.
        -- Unknown history must be conservative: en passant and castling are
        -- disabled until a fresh game is detected, preventing illegal engine
        -- suggestions after lag or very fast consecutive moves.
        BoardTracker.lastMove = nil
        BoardTracker.enPassantSquare = nil
        BoardTracker.halfmoveClock = 0
        BoardTracker.castling.K = false
        BoardTracker.castling.Q = false
        BoardTracker.castling.k = false
        BoardTracker.castling.q = false
        BoardTracker.confirmedTurn = turnHint
        BoardTracker.turnConfidence = turnHint and 1 or 0
        BoardTracker.turnCandidate = turnHint
        BoardTracker.turnCandidateCount = turnHint and 1 or 0
    end

    BoardTracker.lastSnapshot = currentSnapshot
    BoardTracker.lastPieceHash = currentHash
    return move

end

function BoardTracker.parseClockText(text) if type(text) ~= "string"
then return nil end

    text = string.gsub(text, "%s+", "")
    if text == "" or string.find(text, "∞", 1, true) then
        return nil
    end

    local hours, minutes, seconds = string.match(text, "^(%d+):(%d+):(%d+%.?%d*)$")
    if hours then
        return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)
    end

    minutes, seconds = string.match(text, "^(%d+):(%d+%.?%d*)$")
    if minutes then
        return tonumber(minutes) * 60 + tonumber(seconds)
    end

    return tonumber(text)

end

function BoardTracker.findClockLabel(root, targetName)
    if not root then
        return nil
    end
    BoardTracker.clockLabelCache = BoardTracker.clockLabelCache
        or setmetatable({}, { __mode = "k" })
    local perRoot = BoardTracker.clockLabelCache[root]
    if not perRoot then
        perRoot = {}
        BoardTracker.clockLabelCache[root] = perRoot
    end
    local cached = perRoot[targetName]
    if cached and cached:IsDescendantOf(root) then
        return cached
    end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == targetName
            and (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
            perRoot[targetName] = descendant
            return descendant
        end
    end
    return nil
end

function BoardTracker.sampleClockTurn(tableData) local nodes =
BoardTracker.get2DBoardNodes() local clockRoot = nodes and nodes.clocks
or nil local whiteLabel = BoardTracker.findClockLabel(clockRoot,
"WhiteTime") local blackLabel = BoardTracker.findClockLabel(clockRoot,
"BlackTime")

    if (not whiteLabel or not blackLabel) and tableData and tableData.model then
        local workspaceClock = tableData.model:FindFirstChild("Clock")
        whiteLabel = BoardTracker.findClockLabel(workspaceClock, "WhiteTime")
        blackLabel = BoardTracker.findClockLabel(workspaceClock, "BlackTime")
    end

    if not whiteLabel or not blackLabel then
        return BoardTracker.confirmedTurn
    end

    local whiteSeconds = BoardTracker.parseClockText(whiteLabel.Text)
    local blackSeconds = BoardTracker.parseClockText(blackLabel.Text)
    if not whiteSeconds or not blackSeconds then
        return BoardTracker.confirmedTurn
    end

    local detected = nil
    if BoardTracker.lastWhiteClock and BoardTracker.lastBlackClock then
        local whiteChanged = whiteSeconds < BoardTracker.lastWhiteClock - 0.01
        local blackChanged = blackSeconds < BoardTracker.lastBlackClock - 0.01

        if whiteChanged and not blackChanged then
            detected = "white"
        elseif blackChanged and not whiteChanged then
            detected = "black"
        end
    end

    BoardTracker.lastWhiteClock = whiteSeconds
    BoardTracker.lastBlackClock = blackSeconds

    if detected then
        if detected == BoardTracker.turnCandidate then
            BoardTracker.turnCandidateCount += 1
        else
            BoardTracker.turnCandidate = detected
            BoardTracker.turnCandidateCount = 1
        end

        if BoardTracker.turnCandidateCount >= 2 then
            BoardTracker.confirmedTurn = detected
            BoardTracker.turnConfidence = BoardTracker.turnCandidateCount
        end
    end

    return BoardTracker.confirmedTurn

end

function BoardTracker.getSideToMove(fallback) return
BoardTracker.confirmedTurn or fallback end

function BoardTracker.validateBoard(board, diagnostics) local counts = {
white = 0, black = 0, whiteKings = 0, blackKings = 0, whitePawns = 0,
blackPawns = 0, }

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece then
                counts[piece.color] += 1
                if piece.kind == "king" then
                    if piece.color == "white" then
                        counts.whiteKings += 1
                    else
                        counts.blackKings += 1
                    end
                elseif piece.kind == "pawn" then
                    if piece.color == "white" then
                        counts.whitePawns += 1
                    else
                        counts.blackPawns += 1
                    end
                end
            end
        end
    end

    diagnostics.counts = counts
    diagnostics.completeMapping = (diagnostics.recognizedPieces or 0)
            == (diagnostics.mappedPieces or 0)
        and (diagnostics.unmappedPieces or 0) == 0

    diagnostics.valid = counts.whiteKings == 1
        and counts.blackKings == 1
        and counts.white >= 1
        and counts.black >= 1
        and counts.white <= 16
        and counts.black <= 16
        and counts.whitePawns <= 8
        and counts.blackPawns <= 8
        and (diagnostics.collisions or 0) == 0
        and diagnostics.completeMapping

    if not diagnostics.valid then
        if (diagnostics.collisions or 0) > 0 then
            diagnostics.validationError = "Live 2D scan rejected: two piece objects mapped to the same square."
        elseif (diagnostics.unmappedPieces or 0) > 0
            or (diagnostics.recognizedPieces or 0) ~= (diagnostics.mappedPieces or 0) then
            diagnostics.validationError = "Live 2D scan rejected: a piece is between squares or the board is still animating."
        else
            diagnostics.validationError = "Invalid live position: expected one king per side and valid piece counts."
        end
    end

    return diagnostics.valid

end

function BoardTracker.read2DBoard() local nodes =
BoardTracker.get2DBoardNodes() local diagnostics = { source = "2D GUI",
totalObjects = 0, recognizedPieces = 0, mappedPieces = 0, unmappedPieces
= 0, collisions = 0, valid = false, }

    if not nodes then
        diagnostics.validationError = "The live 2D board is not visible."
        return nil, diagnostics
    end

    local squareObjects = {}
    local squareCount = 0

    for _, square in ipairs(nodes.board:GetChildren()) do
        local file, rank = squareCoordinates(square.Name)
        if file and rank and square:IsA("GuiObject") then
            local name = string.lower(square.Name)
            squareObjects[name] = {
                file = file,
                rank = rank,
                layout = Vector2.new(
                    square.Position.X.Scale,
                    square.Position.Y.Scale
                ),
                object = square,
            }
            squareCount += 1
        end
    end

    if squareCount < 64 then
        diagnostics.validationError = "The live 2D board squares are incomplete."
        return nil, diagnostics
    end

    local maximumDistance = 0.09
    local board = createEmptyBoard()
    local occupied = {}

    for _, piece in ipairs(nodes.pieces:GetChildren()) do
        if piece:IsA("ImageButton") then
            diagnostics.totalObjects += 1
            local color, kind = getPieceInformation(piece)
            if color and kind and piece.Visible and piece.ImageTransparency < 0.98 then
                diagnostics.recognizedPieces += 1
                local layout = Vector2.new(
                    piece.Position.X.Scale,
                    piece.Position.Y.Scale
                )
                local closest = nil
                local closestDistance = math.huge

                for name, square in pairs(squareObjects) do
                    local distance = (layout - square.layout).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closest = square
                        closest.name = name
                    end
                end

                if closest and closestDistance <= maximumDistance then
                    local current = occupied[closest.name]
                    if not current or closestDistance < current.distance then
                        if current then
                            diagnostics.collisions += 1
                        end
                        occupied[closest.name] = {
                            distance = closestDistance,
                            color = color,
                            kind = kind,
                            instance = piece,
                            square = closest,
                        }
                    else
                        diagnostics.collisions += 1
                    end
                else
                    diagnostics.unmappedPieces += 1
                end
            end
        end
    end

    for name, occupant in pairs(occupied) do
        local square = occupant.square
        board[square.rank][square.file] = {
            color = occupant.color,
            kind = occupant.kind,
            instance = occupant.instance,
        }
        diagnostics.mappedPieces += 1
    end

    BoardTracker.validateBoard(board, diagnostics)
    diagnostics.boardGui = nodes.gui
    return board, diagnostics

end

local function getBoardSquares(boardFolder) local squares = {}

    if not boardFolder then
        return squares
    end

    for _, square in ipairs(boardFolder:GetChildren()) do
        local file, rank = squareCoordinates(square.Name)
        local position = getObjectPosition(square)

        if file and rank and position then
            local lowerName = string.lower(square.Name)
            squares[lowerName] = {
                name = lowerName,
                file = file,
                rank = rank,
                object = square,
                position = position,
                visualPart = getVisualPart(square),
            }
        end
    end

    return squares

end

local function getTableCenter(squares) local total = Vector3.zero local
count = 0

    for _, square in pairs(squares) do
        total += square.position
        count += 1
    end

    return count > 0 and total / count or nil

end

local function getReferencePosition() local character =
LocalPlayer.Character if character then local rootPart =
character:FindFirstChild("HumanoidRootPart") if rootPart then return
rootPart.Position end end

    local camera = Workspace.CurrentCamera
    return camera and camera.CFrame.Position or Vector3.zero

end

local function findNearestChessTableRaw() local referencePosition =
getReferencePosition() local bestTable = nil local bestDistance =
math.huge local foundTablesetFolder = false

    -- Keep normal-table support and add tournament-table support.
    -- Both layouts use children containing Board and Pieces.
    for _, folderName in ipairs({
        "Tablesets (Main)",
        "Tablesets (Tournament)",
    }) do
        local tablesetsFolder = Workspace:FindFirstChild(folderName)
        if tablesetsFolder then
            foundTablesetFolder = true

            for index, tableModel in ipairs(tablesetsFolder:GetChildren()) do
                local boardFolder = tableModel:FindFirstChild("Board")
                local piecesFolder = tableModel:FindFirstChild("Pieces")

                if boardFolder and piecesFolder then
                    local squares = getBoardSquares(boardFolder)
                    if countDictionary(squares) >= 60 then
                        local center = getTableCenter(squares)
                        if center then
                            local distance = horizontalDistance(
                                center,
                                referencePosition
                            )

                            if distance < bestDistance then
                                bestDistance = distance
                                bestTable = {
                                    model = tableModel,
                                    boardFolder = boardFolder,
                                    piecesFolder = piecesFolder,
                                    squares = squares,
                                    index = index,
                                    distance = distance,
                                    tablesetFolder = tablesetsFolder,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if not foundTablesetFolder then
        return nil, "No main or tournament tablesets folder was found."
    end

    if not bestTable then
        return nil, "No usable table with Board and Pieces was found."
    end

    return bestTable, nil

end

-- The raw search rebuilds every table's 64-square map, so memoise it briefly.
local nearestTableMemo = { value = nil, at = 0 }
local function findNearestChessTable()
    local now = os.clock()
    local value = nearestTableMemo.value
    if value and value.model and value.model.Parent and now - nearestTableMemo.at < 1.0 then
        return value, nil
    end
    local found, problem = findNearestChessTableRaw()
    nearestTableMemo.value = found
    nearestTableMemo.at = now
    return found, problem
end

local function calculateSquareSpacing(squares) local distances = {}
local testPairs = { { "a1", "b1" }, { "a1", "a2" }, { "d4", "e4" }, {
"d4", "d5" }, }

    for _, pair in ipairs(testPairs) do
        local first = squares[pair[1]]
        local second = squares[pair[2]]
        if first and second then
            local distance = horizontalDistance(first.position, second.position)
            if distance > 0.01 then
                table.insert(distances, distance)
            end
        end
    end

    if #distances == 0 then
        return 4
    end

    local total = 0
    for _, distance in ipairs(distances) do
        total += distance
    end
    return total / #distances

end

local function getStoredSquareName(piece) for _, attributeName in
ipairs({ "Square", "Tile", "CurrentSquare", "BoardSquare", }) do local
value = piece:GetAttribute(attributeName) if typeof(value) == "string"
then value = string.lower(value) if string.match(value, "[1][1-8]$")
then return value end end end

    for _, childName in ipairs({ "Tile", "Square", "CurrentSquare" }) do
        local valueObject = piece:FindFirstChild(childName)
        if valueObject then
            if valueObject:IsA("ObjectValue") and valueObject.Value then
                local name = string.lower(valueObject.Value.Name)
                if string.match(name, "^[a-h][1-8]$") then
                    return name
                end
            elseif valueObject:IsA("StringValue") then
                local value = string.lower(valueObject.Value)
                if string.match(value, "^[a-h][1-8]$") then
                    return value
                end
            end
        end
    end

    return nil

end

local function findNearestSquare(piece, squares, maximumDistance) local
storedSquare = getStoredSquareName(piece) if storedSquare and
squares[storedSquare] then return squares[storedSquare], 0 end

    local piecePosition = getObjectPosition(piece)
    if not piecePosition then
        return nil, math.huge
    end

    local closestSquare = nil
    local closestDistance = math.huge

    for _, square in pairs(squares) do
        local distance = horizontalDistance(piecePosition, square.position)
        if distance < closestDistance then
            closestDistance = distance
            closestSquare = square
        end
    end

    if closestDistance <= maximumDistance then
        return closestSquare, closestDistance
    end

    return nil, closestDistance

end

local function readBoard3D(tableData) local board = createEmptyBoard()
local spacing = calculateSquareSpacing(tableData.squares) local
maximumDistance = math.max(spacing * 0.72, 1) local occupied = {}

    local diagnostics = {
        totalObjects = 0,
        recognizedPieces = 0,
        mappedPieces = 0,
        unmappedPieces = 0,
        collisions = 0,
    }

    for _, piece in ipairs(tableData.piecesFolder:GetChildren()) do
        diagnostics.totalObjects += 1

        local color, kind = getPieceInformation(piece)
        if color and kind then
            diagnostics.recognizedPieces += 1

            local square, distance = findNearestSquare(
                piece,
                tableData.squares,
                maximumDistance
            )

            if square then
                local current = occupied[square.name]
                if not current or distance < current.distance then
                    if current then
                        diagnostics.collisions += 1
                    end
                    occupied[square.name] = {
                        distance = distance,
                        instance = piece,
                        color = color,
                        kind = kind,
                    }
                else
                    diagnostics.collisions += 1
                end
            else
                diagnostics.unmappedPieces += 1
            end
        end
    end

    for occupiedSquare, occupant in pairs(occupied) do
        local file, rank = squareCoordinates(occupiedSquare)
        if file and rank then
            board[rank][file] = {
                color = occupant.color,
                kind = occupant.kind,
                instance = occupant.instance,
            }
            diagnostics.mappedPieces += 1
        end
    end

    diagnostics.source = "3D Workspace fallback"
    BoardTracker.validateBoard(board, diagnostics)
    return board, diagnostics

end

local function readBoard(tableData)   if
PlayerGui:FindFirstChild("2DBoard") then BoardTracker.live2DSourceLocked
= true local guiBoard, guiDiagnostics = BoardTracker.read2DBoard()
guiDiagnostics = guiDiagnostics or { source = "2D GUI (locked)",
mappedPieces = 0, valid = false, validationError = "The live 2D board is not ready yet.", } guiDiagnostics.source = "2D GUI (locked; no 3D fallback)" guiDiagnostics.sourceLocked = true return guiBoard,
guiDiagnostics end

    BoardTracker.live2DSourceLocked = false
    local workspaceBoard, workspaceDiagnostics = readBoard3D(tableData)
    if workspaceDiagnostics then
        workspaceDiagnostics.sourceLocked = false
        workspaceDiagnostics.fallbackReason = "The 2D board does not exist in PlayerGui."
    end
    return workspaceBoard, workspaceDiagnostics

end

function BoardTracker.readStableBoard(tableData, attempts) attempts =
math.max( BoardTracker.requiredStableScans, tonumber(attempts) or 6 )
local candidateHash = nil local consecutiveScans = 0 local lastBoard =
nil local lastDiagnostics = nil

    for attempt = 1, attempts do
        local board, diagnostics = readBoard(tableData)
        lastBoard = board
        lastDiagnostics = diagnostics

        if board and diagnostics and diagnostics.valid then
            local hash = BoardTracker.pieceHash(board)
            if hash == candidateHash then
                consecutiveScans += 1
            else
                candidateHash = hash
                consecutiveScans = 1
            end

            if consecutiveScans >= BoardTracker.requiredStableScans then
                diagnostics.stable = true
                diagnostics.stableScans = consecutiveScans
                BoardTracker.lastAcceptedDiagnostics = diagnostics
                return board, diagnostics
            end
        else
            candidateHash = nil
            consecutiveScans = 0
        end

        if attempt < attempts then
            task.wait(0.03)
        end
    end

    if lastDiagnostics then
        lastDiagnostics.stable = false
        lastDiagnostics.stableScans = consecutiveScans
        lastDiagnostics.validationError = lastDiagnostics.validationError
            or "The live 2D position did not remain identical for three scans."
    end
    return lastBoard, lastDiagnostics

end

-- One fresh read that must show the position we just analysed. The analysed position was already
-- confirmed stable, so re-confirming it needs no extra stability waits (the old 5-scan gate cost
-- 0.15 s+ on every single analysis).
function BoardTracker.confirmBoard(tableData, expectedBoard)
    local expectedHash = BoardTracker.pieceHash(expectedBoard)
    local lastBoard, lastDiagnostics = nil, nil
    for attempt = 1, 3 do
        local board, diagnostics = readBoard(tableData)
        lastBoard, lastDiagnostics = board, diagnostics
        if board and diagnostics and diagnostics.valid then
            diagnostics.stable = true
            diagnostics.stableScans = BoardTracker.requiredStableScans
            if BoardTracker.pieceHash(board) == expectedHash then
                BoardTracker.lastAcceptedDiagnostics = diagnostics
            end
            return board, diagnostics
        end
        if attempt < 3 then
            task.wait(0.03)
        end
    end
    if lastDiagnostics then
        lastDiagnostics.stable = false
    end
    return lastBoard, lastDiagnostics
end

local function findKing(board, color) for rank = 1, 8 do for file = 1, 8
do local piece = board[rank][file] if piece and piece.color == color and
piece.kind == "king" then return file, rank end end end return nil, nil
end

local function isSquareAttacked(board, targetFile, targetRank,
attackingColor) local pawnDirection = attackingColor == "white" and 1 or
-1 local pawnSourceRank = targetRank - pawnDirection

    for _, fileOffset in ipairs({ -1, 1 }) do
        local file = targetFile + fileOffset
        local rank = pawnSourceRank
        if inBounds(file, rank) then
            local piece = board[rank][file]
            if piece and piece.color == attackingColor and piece.kind == "pawn" then
                return true
            end
        end
    end

    local knightOffsets = {
        { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 },
        { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 },
    }

    for _, offset in ipairs(knightOffsets) do
        local file = targetFile + offset[1]
        local rank = targetRank + offset[2]
        if inBounds(file, rank) then
            local piece = board[rank][file]
            if piece and piece.color == attackingColor and piece.kind == "knight" then
                return true
            end
        end
    end

    for _, direction in ipairs({
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    }) do
        local file = targetFile + direction[1]
        local rank = targetRank + direction[2]

        while inBounds(file, rank) do
            local piece = board[rank][file]
            if piece then
                if piece.color == attackingColor
                    and (piece.kind == "bishop" or piece.kind == "queen") then
                    return true
                end
                break
            end
            file += direction[1]
            rank += direction[2]
        end
    end

    for _, direction in ipairs({
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    }) do
        local file = targetFile + direction[1]
        local rank = targetRank + direction[2]

        while inBounds(file, rank) do
            local piece = board[rank][file]
            if piece then
                if piece.color == attackingColor
                    and (piece.kind == "rook" or piece.kind == "queen") then
                    return true
                end
                break
            end
            file += direction[1]
            rank += direction[2]
        end
    end

    for fileOffset = -1, 1 do
        for rankOffset = -1, 1 do
            if fileOffset ~= 0 or rankOffset ~= 0 then
                local file = targetFile + fileOffset
                local rank = targetRank + rankOffset
                if inBounds(file, rank) then
                    local piece = board[rank][file]
                    if piece and piece.color == attackingColor and piece.kind == "king" then
                        return true
                    end
                end
            end
        end
    end

    return false

end

local function isKingInCheck(board, color) local kingFile, kingRank =
findKing(board, color) if not kingFile then return true end return
isSquareAttacked(board, kingFile, kingRank, opposite(color)) end

local function addMove( moves, fromFile, fromRank, toFile, toRank,
piece, capture, promotion, special ) local move = { fromFile = fromFile,
fromRank = fromRank, toFile = toFile, toRank = toRank, piece = piece,
capture = capture, promotion = promotion, }

    if type(special) == "table" then
        for key, value in pairs(special) do
            move[key] = value
        end
    end

    table.insert(moves, move)

end

local function canCapture(target, movingColor) return target and
target.color ~= movingColor and target.kind ~= "king" end

 
function BoardTracker.getChessClubKingCaptures(board, color) if not
BoardTracker.chessClubKingCaptureCompatibility then return {} end

    local enemy = opposite(color)
    local kingFile, kingRank = findKing(board, enemy)
    if not kingFile then
        return {}
    end

    local target = board[kingRank][kingFile]
    if not target or target.color == color or target.kind ~= "king" then
        return {}
    end

    local captures = {}

    local function addKingCapture(fromFile, fromRank, piece)
        table.insert(captures, {
            fromFile = fromFile,
            fromRank = fromRank,
            toFile = kingFile,
            toRank = kingRank,
            piece = piece,
            capture = target,
            promotion = nil,
            kingCapture = true,
            chessClubRule = true,
        })
    end

    local function pathIsClear(fromFile, fromRank, stepFile, stepRank)
        local file = fromFile + stepFile
        local rank = fromRank + stepRank
        while file ~= kingFile or rank ~= kingRank do
            if not inBounds(file, rank) or board[rank][file] then
                return false
            end
            file += stepFile
            rank += stepRank
        end
        return true
    end

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece and piece.color == color then
                local fileDelta = kingFile - file
                local rankDelta = kingRank - rank
                local absoluteFile = math.abs(fileDelta)
                local absoluteRank = math.abs(rankDelta)

                if piece.kind == "pawn" then
                    local direction = color == "white" and 1 or -1
                    if rankDelta == direction and absoluteFile == 1 then
                        addKingCapture(file, rank, piece)
                    end
                elseif piece.kind == "knight" then
                    if (absoluteFile == 1 and absoluteRank == 2)
                        or (absoluteFile == 2 and absoluteRank == 1) then
                        addKingCapture(file, rank, piece)
                    end
                elseif piece.kind == "king" then
                    if absoluteFile <= 1 and absoluteRank <= 1
                        and (absoluteFile ~= 0 or absoluteRank ~= 0) then
                        addKingCapture(file, rank, piece)
                    end
                elseif piece.kind == "bishop" or piece.kind == "rook"
                    or piece.kind == "queen" then
                    local diagonal = absoluteFile == absoluteRank and absoluteFile > 0
                    local straight = (fileDelta == 0 and rankDelta ~= 0)
                        or (rankDelta == 0 and fileDelta ~= 0)
                    local allowed = (piece.kind == "bishop" and diagonal)
                        or (piece.kind == "rook" and straight)
                        or (piece.kind == "queen" and (diagonal or straight))

                    if allowed then
                        local stepFile = fileDelta == 0 and 0
                            or (fileDelta > 0 and 1 or -1)
                        local stepRank = rankDelta == 0 and 0
                            or (rankDelta > 0 and 1 or -1)
                        if pathIsClear(file, rank, stepFile, stepRank) then
                            addKingCapture(file, rank, piece)
                        end
                    end
                end
            end
        end
    end

    table.sort(captures, function(left, right)
        local leftValue = PIECE_VALUES[left.piece.kind] or 0
        local rightValue = PIECE_VALUES[right.piece.kind] or 0
        if leftValue ~= rightValue then
            return leftValue < rightValue
        end
        if left.fromRank ~= right.fromRank then
            return left.fromRank < right.fromRank
        end
        return left.fromFile < right.fromFile
    end)

    return captures

end

function BoardTracker.appendCastlingMoves(moves, board, color, file,
rank, piece) if not BoardTracker.matchesCurrentBoard(board) then return
end

    local homeRank = color == "white" and 1 or 8
    if file ~= 5 or rank ~= homeRank or isKingInCheck(board, color) then
        return
    end

    local enemy = opposite(color)
    local kingSideKey = color == "white" and "K" or "k"
    local queenSideKey = color == "white" and "Q" or "q"

    if BoardTracker.castling[kingSideKey] then
        local rook = board[homeRank][8]
        if rook and rook.color == color and rook.kind == "rook"
            and not board[homeRank][6]
            and not board[homeRank][7]
            and not isSquareAttacked(board, 6, homeRank, enemy)
            and not isSquareAttacked(board, 7, homeRank, enemy) then
            addMove(
                moves,
                5,
                homeRank,
                7,
                homeRank,
                piece,
                nil,
                nil,
                {
                    castle = "king",
                    rookFromFile = 8,
                    rookToFile = 6,
                }
            )
        end
    end

    if BoardTracker.castling[queenSideKey] then
        local rook = board[homeRank][1]
        if rook and rook.color == color and rook.kind == "rook"
            and not board[homeRank][2]
            and not board[homeRank][3]
            and not board[homeRank][4]
            and not isSquareAttacked(board, 4, homeRank, enemy)
            and not isSquareAttacked(board, 3, homeRank, enemy) then
            addMove(
                moves,
                5,
                homeRank,
                3,
                homeRank,
                piece,
                nil,
                nil,
                {
                    castle = "queen",
                    rookFromFile = 1,
                    rookToFile = 4,
                }
            )
        end
    end

end

local function generatePseudoLegalMoves(board, color) local moves = {}

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece and piece.color == color then
                if piece.kind == "pawn" then
                    local direction = color == "white" and 1 or -1
                    local startingRank = color == "white" and 2 or 7
                    local promotionRank = color == "white" and 8 or 1
                    local oneStepRank = rank + direction

                    if inBounds(file, oneStepRank) and not board[oneStepRank][file] then
                        if oneStepRank == promotionRank then
                            for _, promotion in ipairs(PROMOTION_PIECES) do
                                addMove(
                                    moves,
                                    file,
                                    rank,
                                    file,
                                    oneStepRank,
                                    piece,
                                    nil,
                                    promotion
                                )
                            end
                        else
                            addMove(
                                moves,
                                file,
                                rank,
                                file,
                                oneStepRank,
                                piece,
                                nil,
                                nil
                            )
                        end

                        local twoStepRank = rank + direction * 2
                        if rank == startingRank
                            and inBounds(file, twoStepRank)
                            and not board[twoStepRank][file] then
                            addMove(
                                moves,
                                file,
                                rank,
                                file,
                                twoStepRank,
                                piece,
                                nil,
                                nil
                            )
                        end
                    end

                    for _, fileOffset in ipairs({ -1, 1 }) do
                        local targetFile = file + fileOffset
                        local targetRank = rank + direction
                        if inBounds(targetFile, targetRank) then
                            local target = board[targetRank][targetFile]
                            if canCapture(target, color) then
                                if targetRank == promotionRank then
                                    for _, promotion in ipairs(PROMOTION_PIECES) do
                                        addMove(
                                            moves,
                                            file,
                                            rank,
                                            targetFile,
                                            targetRank,
                                            piece,
                                            target,
                                            promotion
                                        )
                                    end
                                else
                                    addMove(
                                        moves,
                                        file,
                                        rank,
                                        targetFile,
                                        targetRank,
                                        piece,
                                        target,
                                        nil
                                    )
                                end
                            elseif not target
                                and BoardTracker.matchesCurrentBoard(board)
                                and BoardTracker.enPassantSquare
                                    == squareName(targetFile, targetRank) then
                                local capturedPawn = board[rank][targetFile]
                                if capturedPawn
                                    and capturedPawn.color ~= color
                                    and capturedPawn.kind == "pawn" then
                                    addMove(
                                        moves,
                                        file,
                                        rank,
                                        targetFile,
                                        targetRank,
                                        piece,
                                        capturedPawn,
                                        nil,
                                        {
                                            enPassant = true,
                                            captureFile = targetFile,
                                            captureRank = rank,
                                        }
                                    )
                                end
                            end
                        end
                    end

                elseif piece.kind == "knight" then
                    for _, offset in ipairs({
                        { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 },
                        { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 },
                    }) do
                        local targetFile = file + offset[1]
                        local targetRank = rank + offset[2]
                        if inBounds(targetFile, targetRank) then
                            local target = board[targetRank][targetFile]
                            if not target or canCapture(target, color) then
                                addMove(
                                    moves,
                                    file,
                                    rank,
                                    targetFile,
                                    targetRank,
                                    piece,
                                    target,
                                    nil
                                )
                            end
                        end
                    end

                elseif piece.kind == "bishop"
                    or piece.kind == "rook"
                    or piece.kind == "queen" then
                    local directions = {}

                    if piece.kind == "bishop" or piece.kind == "queen" then
                        table.insert(directions, { 1, 1 })
                        table.insert(directions, { 1, -1 })
                        table.insert(directions, { -1, 1 })
                        table.insert(directions, { -1, -1 })
                    end

                    if piece.kind == "rook" or piece.kind == "queen" then
                        table.insert(directions, { 1, 0 })
                        table.insert(directions, { -1, 0 })
                        table.insert(directions, { 0, 1 })
                        table.insert(directions, { 0, -1 })
                    end

                    for _, direction in ipairs(directions) do
                        local targetFile = file + direction[1]
                        local targetRank = rank + direction[2]

                        while inBounds(targetFile, targetRank) do
                            local target = board[targetRank][targetFile]
                            if not target then
                                addMove(
                                    moves,
                                    file,
                                    rank,
                                    targetFile,
                                    targetRank,
                                    piece,
                                    nil,
                                    nil
                                )
                            else
                                if canCapture(target, color) then
                                    addMove(
                                        moves,
                                        file,
                                        rank,
                                        targetFile,
                                        targetRank,
                                        piece,
                                        target,
                                        nil
                                    )
                                end
                                break
                            end

                            targetFile += direction[1]
                            targetRank += direction[2]
                        end
                    end

                elseif piece.kind == "king" then
                    for fileOffset = -1, 1 do
                        for rankOffset = -1, 1 do
                            if fileOffset ~= 0 or rankOffset ~= 0 then
                                local targetFile = file + fileOffset
                                local targetRank = rank + rankOffset
                                if inBounds(targetFile, targetRank) then
                                    local target = board[targetRank][targetFile]
                                    if not target or canCapture(target, color) then
                                        addMove(
                                            moves,
                                            file,
                                            rank,
                                            targetFile,
                                            targetRank,
                                            piece,
                                            target,
                                            nil
                                        )
                                    end
                                end
                            end
                        end
                    end

                    BoardTracker.appendCastlingMoves(
                        moves,
                        board,
                        color,
                        file,
                        rank,
                        piece
                    )
                end
            end
        end
    end

    return moves

end

local function applyMove(board, move) local newBoard = cloneBoard(board)
local movingPiece = newBoard[move.fromRank][move.fromFile]

    if not movingPiece then
        return newBoard
    end

    newBoard[move.fromRank][move.fromFile] = nil

    if move.enPassant and move.captureFile and move.captureRank then
        newBoard[move.captureRank][move.captureFile] = nil
    end

    newBoard[move.toRank][move.toFile] = {
        color = movingPiece.color,
        kind = move.promotion or movingPiece.kind,
        instance = movingPiece.instance,
    }

    if move.castle and move.rookFromFile and move.rookToFile then
        local rook = newBoard[move.toRank][move.rookFromFile]
        newBoard[move.toRank][move.rookFromFile] = nil
        if rook then
            newBoard[move.toRank][move.rookToFile] = {
                color = rook.color,
                kind = rook.kind,
                instance = rook.instance,
            }
        end
    end

    return newBoard

end

local function generateLegalMoves(board, color) local legalMoves = {}

    for _, move in ipairs(generatePseudoLegalMoves(board, color)) do
        local nextBoard = applyMove(board, move)
        if not isKingInCheck(nextBoard, color) then
            move._nextBoard = nextBoard
            table.insert(legalMoves, move)
        end
    end

    return legalMoves

end

local function moveToCoordinates(move) return squareName(move.fromFile,
move.fromRank) .. squareName(move.toFile, move.toRank) ..
(move.promotion and string.sub(move.promotion, 1, 1) or "") end

local function moveToDisplay(move) return
string.upper(squareName(move.fromFile, move.fromRank)) .. " → " ..
string.upper(squareName(move.toFile, move.toRank)) end

local function moveToNotation(board, move) local destination =
squareName(move.toFile, move.toRank) local notation

    if move.kingCapture or (move.capture and move.capture.kind == "king") then
        if move.piece.kind == "pawn" then
            notation = FILE_NAMES[move.fromFile] .. "x" .. destination .. "#"
        else
            notation = PIECE_LETTERS[move.piece.kind] .. "x" .. destination .. "#"
        end
        return notation
    end

    if move.castle == "king" then
        notation = "O-O"
    elseif move.castle == "queen" then
        notation = "O-O-O"
    elseif move.piece.kind == "pawn" then
        if move.capture then
            notation = FILE_NAMES[move.fromFile] .. "x" .. destination
        else
            notation = destination
        end
    else
        notation = PIECE_LETTERS[move.piece.kind]
            .. (move.capture and "x" or "")
            .. destination
    end

    if move.promotion then
        notation ..= "=" .. PIECE_LETTERS[move.promotion]
    end

    local nextBoard = applyMove(board, move)
    local enemy = opposite(move.piece.color)
    if isKingInCheck(nextBoard, enemy) then
        local replies = generateLegalMoves(nextBoard, enemy)
        notation ..= #replies == 0 and "#" or "+"
    end

    return notation

end

local Claude1 = (function()
--[[
	CLAUDE 5  -  self-contained chess engine (performance + strength successor of Claude 5) (pure Lua/Luau, no external APIs)

	Board        10x12 mailbox, incremental material/PST + Zobrist hashing
	Moves        pseudo-legal generation + make/unmake legality filter, castling, en passant, promotions
	Search       iterative deepening, PVS, transposition table, null-move pruning, reverse futility,
	             futility + late-move pruning, late-move reductions, check extensions, killer + history
	             ordering, SEE-ordered captures, quiescence search, repetition / 50-move draws, MultiPV
	Evaluation   tapered material + piece-square tables, pawn structure (passed / isolated / doubled /
	             connected), mobility, king safety (shield + attack zone), bishop pair, rook files, 7th rank
	Styles       Normal / Aggressive / Defensive / Passive  (evaluation weights, contempt, root tie-breaks)

	Public API (all positions are given as FEN strings):
		Claude1.search(opts) -> result
			opts.fen          position
			opts.timeLimit    seconds (hard limit)         default 1.5
			opts.maxDepth     default 64
			opts.multiPV      number of lines to return    default 3
			opts.style        "Normal"|"Aggressive"|"Defensive"|"Passive"
			opts.yield        function called regularly so the host can stay responsive
			opts.yieldEvery   seconds between yield calls   default 0.012
			opts.cancel       function -> true to abort
			opts.onProgress   function(result) after every completed depth
			opts.minDepth     minimum depth to finish before the time limit may stop the search (default 1)
		result = { lines = { {uci=, score=, depth=, pv={uci,...}} ... }, depth=, nodes=, elapsed=, nps=,
		           timedOut=, cancelled=, noMoves=, inCheck= }
		Scores are centipawns from the SIDE TO MOVE's point of view; mates are +/-(30000 - plies).
		Claude1.evaluate(fen, style) -> centipawns from white's point of view (static)
		Claude1.perft(fen, depth), Claude1.legalMoves(fen), Claude1.clearHash()
]]

local Claude1 = {}
Claude1.NAME = "Claude 5"
Claude1.VERSION = "5.0"
Claude1.STYLES = { "Normal", "Aggressive", "Defensive", "Passive" }

local floor = math.floor
local abs = math.abs
local clock = os.clock
local band = bit32.band
local bxor = bit32.bxor

local INF = 32000
local MATE = 30000
local MATE_BOUND = MATE - 256
local MAXPLY = 96

------------------------------------------------------------------------------------------------
-- constants & tables
------------------------------------------------------------------------------------------------
-- piece codes: 0 empty, 1..6 white P N B R Q K, 9..14 black, 16 off-board
local PTYPE = { [0] = 0 }
local PCOL = { [0] = 0 }
for t = 1, 6 do
	PTYPE[t] = t
	PCOL[t] = 1
	PTYPE[t + 8] = t
	PCOL[t + 8] = 2
end
PTYPE[16] = 0
PCOL[16] = 3

local KN = { 21, 19, 12, 8, -8, -12, -19, -21 }
local KG = { 10, 11, 1, -9, -10, -11, -1, 9 }
local BDIR = { 11, 9, -9, -11 }
local RDIR = { 10, 1, -10, -1 }

local MAT_MG = { 100, 320, 330, 500, 900, 0 }
local MAT_EG = { 110, 310, 335, 520, 940, 0 }
local PHASEW = { 0, 1, 1, 2, 4, 0 }
local SEEV = { 100, 325, 335, 500, 975, 20000 }

-- piece-square tables (white's view, a8..h1 order)
local PST = {
	{ -- pawn
		0, 0, 0, 0, 0, 0, 0, 0,
		50, 50, 50, 50, 50, 50, 50, 50,
		10, 10, 20, 30, 30, 20, 10, 10,
		5, 5, 10, 25, 25, 10, 5, 5,
		0, 0, 0, 20, 20, 0, 0, 0,
		5, -5, -10, 0, 0, -10, -5, 5,
		5, 10, 10, -20, -20, 10, 10, 5,
		0, 0, 0, 0, 0, 0, 0, 0,
	},
	{ -- knight
		-50, -40, -30, -30, -30, -30, -40, -50,
		-40, -20, 0, 0, 0, 0, -20, -40,
		-30, 0, 10, 15, 15, 10, 0, -30,
		-30, 5, 15, 20, 20, 15, 5, -30,
		-30, 0, 15, 20, 20, 15, 0, -30,
		-30, 5, 10, 15, 15, 10, 5, -30,
		-40, -20, 0, 5, 5, 0, -20, -40,
		-50, -40, -30, -30, -30, -30, -40, -50,
	},
	{ -- bishop
		-20, -10, -10, -10, -10, -10, -10, -20,
		-10, 0, 0, 0, 0, 0, 0, -10,
		-10, 0, 5, 10, 10, 5, 0, -10,
		-10, 5, 5, 10, 10, 5, 5, -10,
		-10, 0, 10, 10, 10, 10, 0, -10,
		-10, 10, 10, 10, 10, 10, 10, -10,
		-10, 5, 0, 0, 0, 0, 5, -10,
		-20, -10, -10, -10, -10, -10, -10, -20,
	},
	{ -- rook
		0, 0, 0, 0, 0, 0, 0, 0,
		5, 10, 10, 10, 10, 10, 10, 5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		0, 0, 0, 5, 5, 0, 0, 0,
	},
	{ -- queen
		-20, -10, -10, -5, -5, -10, -10, -20,
		-10, 0, 0, 0, 0, 0, 0, -10,
		-10, 0, 5, 5, 5, 5, 0, -10,
		-5, 0, 5, 5, 5, 5, 0, -5,
		0, 0, 5, 5, 5, 5, 0, -5,
		-10, 5, 5, 5, 5, 5, 0, -10,
		-10, 0, 5, 0, 0, 0, 0, -10,
		-20, -10, -10, -5, -5, -10, -10, -20,
	},
	{ -- king (middlegame)
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-20, -30, -30, -40, -40, -30, -30, -20,
		-10, -20, -20, -20, -20, -20, -20, -10,
		20, 20, 0, 0, 0, 0, 20, 20,
		20, 30, 10, 0, 0, 10, 30, 20,
	},
}
local PST_KING_EG = {
	-50, -40, -30, -20, -20, -30, -40, -50,
	-30, -20, -10, 0, 0, -10, -20, -30,
	-30, -10, 20, 30, 30, 20, -10, -30,
	-30, -10, 30, 40, 40, 30, -10, -30,
	-30, -10, 30, 40, 40, 30, -10, -30,
	-30, -10, 20, 30, 30, 20, -10, -30,
	-30, -30, 0, 0, 0, 0, -30, -30,
	-50, -30, -30, -30, -30, -30, -30, -50,
}
-- endgame pawns: reward advancement more strongly
local PST_PAWN_EG = {
	0, 0, 0, 0, 0, 0, 0, 0,
	90, 90, 90, 90, 90, 90, 90, 90,
	50, 50, 50, 50, 50, 50, 50, 50,
	30, 30, 30, 30, 30, 30, 30, 30,
	15, 15, 15, 15, 15, 15, 15, 15,
	5, 5, 5, 5, 5, 5, 5, 5,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
}

-- per-piece, per-square (120 mailbox) incremental scores; black entries are negative
local PSTMG = {}
local PSTEG = {}
for p = 1, 14 do
	if p ~= 7 and p ~= 8 then
		PSTMG[p] = {}
		PSTEG[p] = {}
	end
end
local SQ64 = {} -- mailbox square -> 1..64 (a1 = 1)
local function sqOf(r, f)
	return 22 + r * 10 + f
end
for r = 0, 7 do
	for f = 0, 7 do
		local sq = sqOf(r, f)
		SQ64[sq] = r * 8 + f + 1
		for t = 1, 6 do
			local whiteRow = (7 - r) * 8 + f + 1
			local blackRow = r * 8 + f + 1
			local mgTable = PST[t]
			local egTable = (t == 6 and PST_KING_EG) or (t == 1 and PST_PAWN_EG) or PST[t]
			local mg0 = MAT_MG[t]
			local eg0 = MAT_EG[t]
			PSTMG[t][sq] = mg0 + mgTable[whiteRow]
			PSTEG[t][sq] = eg0 + egTable[whiteRow]
			PSTMG[t + 8][sq] = -(mg0 + mgTable[blackRow])
			PSTEG[t + 8][sq] = -(eg0 + egTable[blackRow])
		end
	end
end

-- RAYDIR[a][b]: step (+-1, +-9, +-10, +-11) from a towards b when they share a rank/file/diagonal, else 0
local RAYDIR = {}
do
	for a = 22, 99 do
		local ar, af = (a - 22) // 10, (a - 22) % 10
		if af <= 7 then
			local row = {}
			RAYDIR[a] = row
			for b = 22, 99 do
				local br, bf = (b - 22) // 10, (b - 22) % 10
				local step = 0
				if bf <= 7 and a ~= b then
					local dr, df = br - ar, bf - af
					if dr == 0 then
						step = (df > 0) and 1 or -1
					elseif df == 0 then
						step = (dr > 0) and 10 or -10
					elseif dr == df or dr == -df then
						step = ((dr > 0) and 10 or -10) + ((df > 0) and 1 or -1)
					end
				end
				row[b] = step
			end
		end
	end
end

-- Zobrist keys (two independent 32-bit halves)
local zseed = 0x2545F491
local function rand32()
	zseed = bxor(zseed, (zseed % 524288) * 8192)
	zseed = bxor(zseed, zseed // 131072)
	zseed = bxor(zseed, (zseed % 134217728) * 32)
	return zseed
end
local Z1, Z2 = {}, {}
for p = 1, 14 do
	for sq = 0, 127 do
		Z1[p * 128 + sq] = rand32()
		Z2[p * 128 + sq] = rand32()
	end
end
local ZC1, ZC2 = {}, {}
for i = 0, 15 do
	ZC1[i] = rand32()
	ZC2[i] = rand32()
end
local ZE1, ZE2 = {}, {}
for i = 0, 127 do
	ZE1[i] = rand32()
	ZE2[i] = rand32()
end
local ZS1, ZS2 = rand32(), rand32()

-- castling rights lost when a move touches these squares
local CMASK = {}
for i = 1, 120 do
	CMASK[i] = 15
end
CMASK[26] = 15 - 1 - 2 -- e1
CMASK[22] = 15 - 2 -- a1
CMASK[29] = 15 - 1 -- h1
CMASK[96] = 15 - 4 - 8 -- e8
CMASK[92] = 15 - 8 -- a8
CMASK[99] = 15 - 4 -- h8

------------------------------------------------------------------------------------------------
-- position state
------------------------------------------------------------------------------------------------
local board = {}
for i = 1, 120 do
	board[i] = 16
end
local side = 1 -- 1 white, 2 black
local castle = 0
local ep = 0
local half = 0
local fullmove = 1
local kingSq1, kingSq2 = 0, 0
local qsq1, qsq2 = 0, 0 -- last known queen squares (for the hunted-queen extension)
local PLS = { {}, {} } -- piece lists: squares of each side's pieces (move generation and evaluation visit only real pieces)
local PLNUM = { 0, 0 }
local PLIDX = {} -- square -> index in its side's list
local PLUNDO = {} -- per stack ply: index the captured piece had (swap-remove undo)
local h1, h2 = 0, 0
local mgS, egS, phase = 0, 0, 0
local npm1, npm2 = 0, 0 -- knights/bishops/rooks/queens per side
local sp = 1

local posH1, posH2 = {}, {}
local uCapt, uCastle, uEp, uHalf, uH1, uH2, uMg, uEg, uPh, uK1, uK2 = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local uN1, uN2 = {}, {}
local uQ1, uQ2 = {}, {}
for i = 1, 1024 do
	posH1[i], posH2[i] = 0, 0
	uCapt[i], uCastle[i], uEp[i], uHalf[i] = 0, 0, 0, 0
	uH1[i], uH2[i], uMg[i], uEg[i], uPh[i], uK1[i], uK2[i] = 0, 0, 0, 0, 0, 0, 0
	uN1[i], uN2[i] = 0, 0
	uQ1[i], uQ2[i] = 0, 0
end

------------------------------------------------------------------------------------------------
-- attack detection
------------------------------------------------------------------------------------------------
local function isAttacked(sq, by)
	if by == 1 then
		if board[sq - 9] == 1 or board[sq - 11] == 1 then
			return true
		end
		for i = 1, 8 do
			if board[sq + KN[i]] == 2 then
				return true
			end
		end
		for i = 1, 8 do
			if board[sq + KG[i]] == 6 then
				return true
			end
		end
		for i = 1, 4 do
			local d = BDIR[i]
			local s = sq + d
			local p = board[s]
			while p == 0 do
				s = s + d
				p = board[s]
			end
			if p == 3 or p == 5 then
				return true
			end
		end
		for i = 1, 4 do
			local d = RDIR[i]
			local s = sq + d
			local p = board[s]
			while p == 0 do
				s = s + d
				p = board[s]
			end
			if p == 4 or p == 5 then
				return true
			end
		end
	else
		if board[sq + 9] == 9 or board[sq + 11] == 9 then
			return true
		end
		for i = 1, 8 do
			if board[sq + KN[i]] == 10 then
				return true
			end
		end
		for i = 1, 8 do
			if board[sq + KG[i]] == 14 then
				return true
			end
		end
		for i = 1, 4 do
			local d = BDIR[i]
			local s = sq + d
			local p = board[s]
			while p == 0 do
				s = s + d
				p = board[s]
			end
			if p == 11 or p == 13 then
				return true
			end
		end
		for i = 1, 4 do
			local d = RDIR[i]
			local s = sq + d
			local p = board[s]
			while p == 0 do
				s = s + d
				p = board[s]
			end
			if p == 12 or p == 13 then
				return true
			end
		end
	end
	return false
end

local function inCheck()
	if side == 1 then
		return isAttacked(kingSq1, 2)
	end
	return isAttacked(kingSq2, 1)
end

------------------------------------------------------------------------------------------------
-- move generation   move = from + 128*to + 16384*promo + 131072*flag
-- flag: 1 double push, 2 en passant, 3 castle king-side, 4 castle queen-side
------------------------------------------------------------------------------------------------
local function generate(list, caps)
	local n = 0
	local us = side
	local them = 3 - us
	local up, startR, promoR
	if us == 1 then
		up, startR, promoR = 10, 1, 6
	else
		up, startR, promoR = -10, 6, 1
	end
	local plist = PLS[us]
	for li = 1, PLNUM[us] do
		do
			local sq = plist[li]
			local r = (sq - 22) // 10
			local p = board[sq]
			if p ~= 0 and PCOL[p] == us then
				local t = PTYPE[p]
				if t == 1 then
					local to = sq + up
					if board[to] == 0 then
						if r == promoR then
							n = n + 1
							list[n] = sq + 128 * to + 16384 * 5
							if not caps then
								list[n + 1] = sq + 128 * to + 16384 * 4
								list[n + 2] = sq + 128 * to + 16384 * 3
								list[n + 3] = sq + 128 * to + 16384 * 2
								n = n + 3
							end
						elseif not caps then
							n = n + 1
							list[n] = sq + 128 * to
							if r == startR and board[to + up] == 0 then
								n = n + 1
								list[n] = sq + 128 * (to + up) + 131072
							end
						end
					end
					for k = -1, 1, 2 do
						local cto = sq + up + k
						local tp = board[cto]
						if tp ~= 0 and tp ~= 16 and PCOL[tp] == them then
							if r == promoR then
								n = n + 1
								list[n] = sq + 128 * cto + 16384 * 5
								if not caps then
									list[n + 1] = sq + 128 * cto + 16384 * 4
									list[n + 2] = sq + 128 * cto + 16384 * 3
									list[n + 3] = sq + 128 * cto + 16384 * 2
									n = n + 3
								end
							else
								n = n + 1
								list[n] = sq + 128 * cto
							end
						elseif cto == ep and tp == 0 then
							n = n + 1
							list[n] = sq + 128 * cto + 131072 * 2
						end
					end
				elseif t == 2 then
					for i = 1, 8 do
						local to = sq + KN[i]
						local tp = board[to]
						if tp == 0 then
							if not caps then
								n = n + 1
								list[n] = sq + 128 * to
							end
						elseif tp ~= 16 and PCOL[tp] == them then
							n = n + 1
							list[n] = sq + 128 * to
						end
					end
				elseif t == 6 then
					for i = 1, 8 do
						local to = sq + KG[i]
						local tp = board[to]
						if tp == 0 then
							if not caps then
								n = n + 1
								list[n] = sq + 128 * to
							end
						elseif tp ~= 16 and PCOL[tp] == them then
							n = n + 1
							list[n] = sq + 128 * to
						end
					end
					if not caps then
						if us == 1 then
							if sq == 26 then
								if band(castle, 1) ~= 0 and board[27] == 0 and board[28] == 0 and board[29] == 4
									and not isAttacked(26, 2) and not isAttacked(27, 2) then
									n = n + 1
									list[n] = 26 + 128 * 28 + 131072 * 3
								end
								if band(castle, 2) ~= 0 and board[25] == 0 and board[24] == 0 and board[23] == 0
									and board[22] == 4 and not isAttacked(26, 2) and not isAttacked(25, 2) then
									n = n + 1
									list[n] = 26 + 128 * 24 + 131072 * 4
								end
							end
						else
							if sq == 96 then
								if band(castle, 4) ~= 0 and board[97] == 0 and board[98] == 0 and board[99] == 12
									and not isAttacked(96, 1) and not isAttacked(97, 1) then
									n = n + 1
									list[n] = 96 + 128 * 98 + 131072 * 3
								end
								if band(castle, 8) ~= 0 and board[95] == 0 and board[94] == 0 and board[93] == 0
									and board[92] == 12 and not isAttacked(96, 1) and not isAttacked(95, 1) then
									n = n + 1
									list[n] = 96 + 128 * 94 + 131072 * 4
								end
							end
						end
					end
				else
					local dirs, nd
					if t == 3 then
						dirs, nd = BDIR, 4
					elseif t == 4 then
						dirs, nd = RDIR, 4
					end
					if t == 5 then
						for pass = 1, 2 do
							local dd = (pass == 1) and BDIR or RDIR
							for i = 1, 4 do
								local d = dd[i]
								local to = sq + d
								local tp = board[to]
								while tp == 0 do
									if not caps then
										n = n + 1
										list[n] = sq + 128 * to
									end
									to = to + d
									tp = board[to]
								end
								if tp ~= 16 and PCOL[tp] == them then
									n = n + 1
									list[n] = sq + 128 * to
								end
							end
						end
					else
						for i = 1, nd do
							local d = dirs[i]
							local to = sq + d
							local tp = board[to]
							while tp == 0 do
								if not caps then
									n = n + 1
									list[n] = sq + 128 * to
								end
								to = to + d
								tp = board[to]
							end
							if tp ~= 16 and PCOL[tp] == them then
								n = n + 1
								list[n] = sq + 128 * to
							end
						end
					end
				end
			end
		end
	end
	return n
end

------------------------------------------------------------------------------------------------
-- make / unmake
------------------------------------------------------------------------------------------------
local function makeMove(m, inChk)
	local from = m % 128
	local rest = m // 128
	local to = rest % 128
	rest = rest // 128
	local promo = rest % 8
	local flag = rest // 8
	local us = side
	local p = board[from]
	local captured = board[to]
	local s0 = sp

	uCastle[s0], uEp[s0], uHalf[s0] = castle, ep, half
	uH1[s0], uH2[s0] = h1, h2
	uMg[s0], uEg[s0], uPh[s0] = mgS, egS, phase
	uK1[s0], uK2[s0] = kingSq1, kingSq2
	uN1[s0], uN2[s0] = npm1, npm2
	uQ1[s0], uQ2[s0] = qsq1, qsq2

	local nh1, nh2 = h1, h2
	local nmg, neg, nph = mgS, egS, phase

	-- lift the moving piece
	nh1 = bxor(nh1, Z1[p * 128 + from])
	nh2 = bxor(nh2, Z2[p * 128 + from])
	nmg = nmg - PSTMG[p][from]
	neg = neg - PSTEG[p][from]
	board[from] = 0

	if flag == 2 then
		local capSq = (us == 1) and (to - 10) or (to + 10)
		captured = board[capSq]
		board[capSq] = 0
		do
			local them = 3 - us
			local ci = PLIDX[capSq]
			local last = PLNUM[them]
			local lastSq = PLS[them][last]
			PLS[them][ci] = lastSq
			PLIDX[lastSq] = ci
			PLNUM[them] = last - 1
			PLUNDO[s0] = ci
		end
		nh1 = bxor(nh1, Z1[captured * 128 + capSq])
		nh2 = bxor(nh2, Z2[captured * 128 + capSq])
		nmg = nmg - PSTMG[captured][capSq]
		neg = neg - PSTEG[captured][capSq]
	elseif captured ~= 0 then
		do
			local them = 3 - us
			local ci = PLIDX[to]
			local last = PLNUM[them]
			local lastSq = PLS[them][last]
			PLS[them][ci] = lastSq
			PLIDX[lastSq] = ci
			PLNUM[them] = last - 1
			PLUNDO[s0] = ci
		end
		nh1 = bxor(nh1, Z1[captured * 128 + to])
		nh2 = bxor(nh2, Z2[captured * 128 + to])
		nmg = nmg - PSTMG[captured][to]
		neg = neg - PSTEG[captured][to]
		nph = nph - PHASEW[PTYPE[captured]]
		if captured > 8 then
			if captured ~= 9 then npm2 = npm2 - 1 end
		elseif captured ~= 1 then
			npm1 = npm1 - 1
		end
	end
	uCapt[s0] = captured
	do
		local mi = PLIDX[from]
		PLS[us][mi] = to
		PLIDX[to] = mi
	end

	local np = p
	if promo ~= 0 then
		np = promo + ((us == 2) and 8 or 0)
		nph = nph + PHASEW[promo]
		if us == 1 then npm1 = npm1 + 1 else npm2 = npm2 + 1 end
	end
	board[to] = np
	nh1 = bxor(nh1, Z1[np * 128 + to])
	nh2 = bxor(nh2, Z2[np * 128 + to])
	nmg = nmg + PSTMG[np][to]
	neg = neg + PSTEG[np][to]

	if flag == 3 then
		local rf, rt = to + 1, to - 1
		local rook = board[rf]
		board[rf] = 0
		board[rt] = rook
		local ri = PLIDX[rf]
		PLS[us][ri] = rt
		PLIDX[rt] = ri
		nh1 = bxor(bxor(nh1, Z1[rook * 128 + rf]), Z1[rook * 128 + rt])
		nh2 = bxor(bxor(nh2, Z2[rook * 128 + rf]), Z2[rook * 128 + rt])
		nmg = nmg - PSTMG[rook][rf] + PSTMG[rook][rt]
		neg = neg - PSTEG[rook][rf] + PSTEG[rook][rt]
	elseif flag == 4 then
		local rf, rt = to - 2, to + 1
		local rook = board[rf]
		board[rf] = 0
		board[rt] = rook
		local ri = PLIDX[rf]
		PLS[us][ri] = rt
		PLIDX[rt] = ri
		nh1 = bxor(bxor(nh1, Z1[rook * 128 + rf]), Z1[rook * 128 + rt])
		nh2 = bxor(bxor(nh2, Z2[rook * 128 + rf]), Z2[rook * 128 + rt])
		nmg = nmg - PSTMG[rook][rf] + PSTMG[rook][rt]
		neg = neg - PSTEG[rook][rf] + PSTEG[rook][rt]
	end

	if p == 6 then
		kingSq1 = to
	elseif p == 14 then
		kingSq2 = to
	end
	if np == 5 then
		qsq1 = to
	elseif np == 13 then
		qsq2 = to
	end
	if captured == 5 then
		qsq1 = (qsq1 == to) and 0 or qsq1
	elseif captured == 13 then
		qsq2 = (qsq2 == to) and 0 or qsq2
	end

	-- castling rights, en passant, clocks, side
	local oldCastle = castle
	castle = band(band(castle, CMASK[from]), CMASK[to])
	if castle ~= oldCastle then
		nh1 = bxor(bxor(nh1, ZC1[oldCastle]), ZC1[castle])
		nh2 = bxor(bxor(nh2, ZC2[oldCastle]), ZC2[castle])
	end
	if ep ~= 0 then
		nh1 = bxor(nh1, ZE1[ep])
		nh2 = bxor(nh2, ZE2[ep])
	end
	if flag == 1 then
		ep = (from + to) // 2
		nh1 = bxor(nh1, ZE1[ep])
		nh2 = bxor(nh2, ZE2[ep])
	else
		ep = 0
	end
	if PTYPE[p] == 1 or captured ~= 0 then
		half = 0
	else
		half = half + 1
	end
	side = 3 - us
	nh1 = bxor(nh1, ZS1)
	nh2 = bxor(nh2, ZS2)

	h1, h2, mgS, egS, phase = nh1, nh2, nmg, neg, nph
	sp = s0 + 1
	posH1[sp], posH2[sp] = h1, h2

	-- legality: our own king must not be attacked
	local ksq = (us == 1) and kingSq1 or kingSq2
	local legalMove
	if p == 6 or p == 14 or flag == 2 or inChk ~= false then
		legalMove = not isAttacked(ksq, 3 - us)
	else
		-- our king was safe before the move: only a discovered attack through `from` can hurt it
		local step = RAYDIR[ksq][from]
		legalMove = true
		if step ~= 0 then
			local sq = ksq + step
			local q = board[sq]
			while q == 0 do
				sq = sq + step
				q = board[sq]
			end
			if us == 1 then
				if step == 1 or step == -1 or step == 10 or step == -10 then
					if q == 12 or q == 13 then legalMove = false end
				elseif q == 11 or q == 13 then
					legalMove = false
				end
			else
				if step == 1 or step == -1 or step == 10 or step == -10 then
					if q == 4 or q == 5 then legalMove = false end
				elseif q == 3 or q == 5 then
					legalMove = false
				end
			end
		end
	end
	if not legalMove then
		-- undo
		sp = s0
		side = us
		local piece = board[to]
		if promo ~= 0 then
			piece = (us == 1) and 1 or 9
		end
		board[from] = piece
		if flag == 2 then
			board[to] = 0
			local capSq = (us == 1) and (to - 10) or (to + 10)
			board[capSq] = uCapt[s0]
		else
			board[to] = uCapt[s0]
		end
		if flag == 3 then
			board[to + 1] = board[to - 1]
			board[to - 1] = 0
			local ri = PLIDX[to - 1]
			PLS[us][ri] = to + 1
			PLIDX[to + 1] = ri
		elseif flag == 4 then
			board[to - 2] = board[to + 1]
			board[to + 1] = 0
			local ri = PLIDX[to + 1]
			PLS[us][ri] = to - 2
			PLIDX[to - 2] = ri
		end
		do
			local mi = PLIDX[to]
			PLS[us][mi] = from
			PLIDX[from] = mi
		end
		if uCapt[s0] ~= 0 then
			local them = 3 - us
			local cs = (flag == 2) and ((us == 1) and (to - 10) or (to + 10)) or to
			local ci = PLUNDO[s0]
			local last = PLNUM[them] + 1
			local atCi = PLS[them][ci]
			PLS[them][last] = atCi
			PLIDX[atCi] = last
			PLS[them][ci] = cs
			PLIDX[cs] = ci
			PLNUM[them] = last
		end
		castle, ep, half = uCastle[s0], uEp[s0], uHalf[s0]
		h1, h2 = uH1[s0], uH2[s0]
		mgS, egS, phase = uMg[s0], uEg[s0], uPh[s0]
		kingSq1, kingSq2 = uK1[s0], uK2[s0]
		npm1, npm2 = uN1[s0], uN2[s0]
		qsq1, qsq2 = uQ1[s0], uQ2[s0]
		return false
	end
	return true
end

local function unmakeMove(m)
	local from = m % 128
	local rest = m // 128
	local to = rest % 128
	rest = rest // 128
	local promo = rest % 8
	local flag = rest // 8
	sp = sp - 1
	local s0 = sp
	local us = 3 - side
	side = us
	local piece = board[to]
	if promo ~= 0 then
		piece = (us == 1) and 1 or 9
	end
	board[from] = piece
	if flag == 2 then
		board[to] = 0
		local capSq = (us == 1) and (to - 10) or (to + 10)
		board[capSq] = uCapt[s0]
	else
		board[to] = uCapt[s0]
	end
	if flag == 3 then
		board[to + 1] = board[to - 1]
		board[to - 1] = 0
		local ri = PLIDX[to - 1]
		PLS[us][ri] = to + 1
		PLIDX[to + 1] = ri
	elseif flag == 4 then
		board[to - 2] = board[to + 1]
		board[to + 1] = 0
		local ri = PLIDX[to + 1]
		PLS[us][ri] = to - 2
		PLIDX[to - 2] = ri
	end
	do
		local mi = PLIDX[to]
		PLS[us][mi] = from
		PLIDX[from] = mi
	end
	if uCapt[s0] ~= 0 then
		local them = 3 - us
		local cs = (flag == 2) and ((us == 1) and (to - 10) or (to + 10)) or to
		local ci = PLUNDO[s0]
		local last = PLNUM[them] + 1
		local atCi = PLS[them][ci]
		PLS[them][last] = atCi
		PLIDX[atCi] = last
		PLS[them][ci] = cs
		PLIDX[cs] = ci
		PLNUM[them] = last
	end
	castle, ep, half = uCastle[s0], uEp[s0], uHalf[s0]
	h1, h2 = uH1[s0], uH2[s0]
	mgS, egS, phase = uMg[s0], uEg[s0], uPh[s0]
	kingSq1, kingSq2 = uK1[s0], uK2[s0]
	npm1, npm2 = uN1[s0], uN2[s0]
	qsq1, qsq2 = uQ1[s0], uQ2[s0]
end

local function makeNull()
	local s0 = sp
	uEp[s0], uH1[s0], uH2[s0], uHalf[s0] = ep, h1, h2, half
	if ep ~= 0 then
		h1 = bxor(h1, ZE1[ep])
		h2 = bxor(h2, ZE2[ep])
	end
	ep = 0
	half = half + 1
	side = 3 - side
	h1 = bxor(h1, ZS1)
	h2 = bxor(h2, ZS2)
	sp = s0 + 1
	posH1[sp], posH2[sp] = h1, h2
end

local function unmakeNull()
	sp = sp - 1
	local s0 = sp
	side = 3 - side
	ep, h1, h2, half = uEp[s0], uH1[s0], uH2[s0], uHalf[s0]
end

------------------------------------------------------------------------------------------------
-- FEN
------------------------------------------------------------------------------------------------
local FEN_PIECE = {
	P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6,
	p = 9, n = 10, b = 11, r = 12, q = 13, k = 14,
}
local PIECE_FEN = { "P", "N", "B", "R", "Q", "K", [9] = "p", [10] = "n", [11] = "b", [12] = "r", [13] = "q", [14] = "k" }

local function recompute()
	h1, h2, mgS, egS, phase = 0, 0, 0, 0, 0
	npm1, npm2 = 0, 0
	qsq1, qsq2 = 0, 0
	PLNUM[1], PLNUM[2] = 0, 0
	for r = 0, 7 do
		for f = 0, 7 do
			local sq = sqOf(r, f)
			local p = board[sq]
			if p ~= 0 then
				local pc = PCOL[p]
				local pn = PLNUM[pc] + 1
				PLNUM[pc] = pn
				PLS[pc][pn] = sq
				PLIDX[sq] = pn
				h1 = bxor(h1, Z1[p * 128 + sq])
				h2 = bxor(h2, Z2[p * 128 + sq])
				mgS = mgS + PSTMG[p][sq]
				egS = egS + PSTEG[p][sq]
				phase = phase + PHASEW[PTYPE[p]]
				local pt = PTYPE[p]
				if pt >= 2 and pt <= 5 then
					if p < 9 then npm1 = npm1 + 1 else npm2 = npm2 + 1 end
				end
				if p == 6 then
					kingSq1 = sq
				elseif p == 14 then
					kingSq2 = sq
				elseif p == 5 then
					qsq1 = sq
				elseif p == 13 then
					qsq2 = sq
				end
			end
		end
	end
	h1 = bxor(h1, ZC1[castle])
	h2 = bxor(h2, ZC2[castle])
	if ep ~= 0 then
		h1 = bxor(h1, ZE1[ep])
		h2 = bxor(h2, ZE2[ep])
	end
	if side == 2 then
		h1 = bxor(h1, ZS1)
		h2 = bxor(h2, ZS2)
	end
end

local function setFen(fen)
	for i = 1, 120 do
		board[i] = 16
	end
	for r = 0, 7 do
		for f = 0, 7 do
			board[sqOf(r, f)] = 0
		end
	end
	local placement, stm, cast, eps, hm, fm = string.match(fen, "^%s*(%S+)%s+(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
	if not placement then
		return false
	end
	local r, f = 7, 0
	for ch in string.gmatch(placement, ".") do
		if ch == "/" then
			r = r - 1
			f = 0
		elseif string.match(ch, "%d") then
			f = f + tonumber(ch)
		else
			local p = FEN_PIECE[ch]
			if not p or r < 0 or f > 7 then
				return false
			end
			board[sqOf(r, f)] = p
			f = f + 1
		end
	end
	side = (stm == "b") and 2 or 1
	castle = 0
	if cast and cast ~= "-" then
		if string.find(cast, "K", 1, true) then castle = castle + 1 end
		if string.find(cast, "Q", 1, true) then castle = castle + 2 end
		if string.find(cast, "k", 1, true) then castle = castle + 4 end
		if string.find(cast, "q", 1, true) then castle = castle + 8 end
	end
	ep = 0
	if eps and eps ~= "-" and #eps == 2 then
		local ef = string.byte(eps, 1) - 97
		local er = tonumber(string.sub(eps, 2, 2))
		if ef >= 0 and ef <= 7 and er then
			ep = sqOf(er - 1, ef)
		end
	end
	half = tonumber(hm) or 0
	fullmove = tonumber(fm) or 1
	kingSq1, kingSq2 = 0, 0
	recompute()
	if kingSq1 == 0 or kingSq2 == 0 then
		return false
	end
	-- the side that is NOT to move can never be in check in a legal position: reject it
	if isAttacked((side == 1) and kingSq2 or kingSq1, side) then
		return false
	end
	-- castling rights are only kept when king and rook really stand on their home squares
	if board[26] ~= 6 then castle = band(castle, 12) end
	if board[96] ~= 14 then castle = band(castle, 3) end
	if board[29] ~= 4 then castle = band(castle, 14) end
	if board[22] ~= 4 then castle = band(castle, 13) end
	if board[99] ~= 12 then castle = band(castle, 11) end
	if board[92] ~= 12 then castle = band(castle, 7) end
	-- an en-passant square is only meaningful if a pawn can really capture there
	if ep ~= 0 then
		local ok = false
		if side == 1 then
			ok = board[ep - 9] == 1 or board[ep - 11] == 1
		else
			ok = board[ep + 9] == 9 or board[ep + 11] == 9
		end
		if not ok then
			ep = 0
		end
	end
	recompute()
	sp = 1
	posH1[1], posH2[1] = h1, h2
	return true
end

local function sqName(sq)
	local r = (sq - 22) // 10
	local f = (sq - 22) % 10
	return string.char(97 + f) .. tostring(r + 1)
end

local PROMO_CHAR = { [2] = "n", [3] = "b", [4] = "r", [5] = "q" }
local function moveToUci(m)
	local from = m % 128
	local rest = m // 128
	local to = rest % 128
	local promo = (rest // 128) % 8
	return sqName(from) .. sqName(to) .. (PROMO_CHAR[promo] or "")
end

------------------------------------------------------------------------------------------------
-- static exchange evaluation
------------------------------------------------------------------------------------------------
local seeGain = {}
local seeRemSq, seeRemPc = {}, {}

local function leastAttacker(sq, col)
	if col == 1 then
		if board[sq - 9] == 1 then return sq - 9 end
		if board[sq - 11] == 1 then return sq - 11 end
	else
		if board[sq + 9] == 9 then return sq + 9 end
		if board[sq + 11] == 9 then return sq + 11 end
	end
	local kn = (col == 1) and 2 or 10
	for i = 1, 8 do
		local s = sq + KN[i]
		if board[s] == kn then return s end
	end
	local b = (col == 1) and 3 or 11
	local r = (col == 1) and 4 or 12
	local q = (col == 1) and 5 or 13
	local k = (col == 1) and 6 or 14
	local qsq = 0
	for i = 1, 4 do
		local d = BDIR[i]
		local s = sq + d
		local p = board[s]
		while p == 0 do
			s = s + d
			p = board[s]
		end
		if p == b then return s end
		if p == q and qsq == 0 then qsq = s end
	end
	for i = 1, 4 do
		local d = RDIR[i]
		local s = sq + d
		local p = board[s]
		while p == 0 do
			s = s + d
			p = board[s]
		end
		if p == r then return s end
		if p == q and qsq == 0 then qsq = s end
	end
	if qsq ~= 0 then return qsq end
	for i = 1, 8 do
		local s = sq + KG[i]
		if board[s] == k then return s end
	end
	return 0
end

local function see(m)
	local from = m % 128
	local rest = m // 128
	local to = rest % 128
	local flag = (rest // 128) // 8
	local target = board[to]
	local value0
	if flag == 2 then
		value0 = SEEV[1]
	elseif target ~= 0 then
		value0 = SEEV[PTYPE[target]]
	else
		value0 = 0
	end
	local piece = board[from]
	local col = PCOL[piece]
	local ptv = SEEV[PTYPE[piece]]
	local gain = seeGain
	gain[0] = value0
	local d = 0
	local nrem = 1
	seeRemSq[1], seeRemPc[1] = from, piece
	board[from] = 0
	while true do
		d = d + 1
		gain[d] = ptv - gain[d - 1]
		if (-gain[d - 1] > gain[d] and -gain[d - 1] or gain[d]) < 0 then
			break
		end
		col = 3 - col
		local asq = leastAttacker(to, col)
		if asq == 0 then
			break
		end
		local ap = board[asq]
		ptv = SEEV[PTYPE[ap]]
		nrem = nrem + 1
		seeRemSq[nrem], seeRemPc[nrem] = asq, ap
		board[asq] = 0
	end
	for i = 1, nrem do
		board[seeRemSq[i]] = seeRemPc[i]
	end
	d = d - 1
	while d > 0 do
		local a, b = -gain[d - 1], gain[d]
		gain[d - 1] = -(a > b and a or b)
		d = d - 1
	end
	return gain[0]
end

------------------------------------------------------------------------------------------------
-- styles
------------------------------------------------------------------------------------------------
-- mob: mobility weight, atkFor: weight of attacks on the opponent king, atkAgainst: weight of attacks
-- on our own king, shield: own pawn shield, struct: pawn structure, passed: passed pawns,
-- draw: value of a draw for the engine (negative = avoids draws), advance: reward for pawn advances
local STYLE_PARAMS = {
	-- archetypes
	Normal = { arch = "N", gambit = 40, dev = 1.0, simplify = 1.0, mob = 1.0, atkFor = 1.0, atkAgainst = 1.0, shield = 1.0, struct = 1.0, passed = 1.0, draw = 0, advance = 0, rootCapture = 0, rootCheck = 0, rootQuiet = 0, rootCastle = 4 },
	Aggressive = { arch = "A", gambit = 120, dev = 1.2, simplify = 0.5, mob = 1.25, atkFor = 1.7, atkAgainst = 0.8, shield = 0.7, struct = 0.9, passed = 1.1, draw = -35, advance = 1.0, rootCapture = 7, rootCheck = 10, rootQuiet = 0, rootCastle = 0 },
	Defensive = { arch = "D", gambit = 15, dev = 1.0, simplify = 1.2, mob = 0.95, atkFor = 0.8, atkAgainst = 1.4, shield = 1.7, struct = 1.2, passed = 1.0, draw = 15, advance = -0.5, rootCapture = 0, rootCheck = 0, rootQuiet = 2, rootCastle = 10 },
	Passive = { arch = "P", gambit = 10, dev = 0.9, simplify = 1.5, mob = 0.8, atkFor = 0.5, atkAgainst = 1.3, shield = 1.4, struct = 1.5, passed = 0.9, draw = 30, advance = -1.5, rootCapture = -3, rootCheck = -4, rootQuiet = 6, rootCastle = 8 },
	-- famous players (approximate playing character, not imitation of their games)
	Tal = { arch = "A", gambit = 180, dev = 1.3, simplify = 0.3, mob = 1.3, atkFor = 2.0, atkAgainst = 0.7, shield = 0.6, struct = 0.8, passed = 1.1, draw = -50, advance = 1.5, rootCapture = 10, rootCheck = 12, rootQuiet = -2, rootCastle = 0 },
	Petrosian = { arch = "D", gambit = 10, dev = 0.9, simplify = 1.3, mob = 0.9, atkFor = 0.6, atkAgainst = 1.8, shield = 1.8, struct = 1.3, passed = 1.0, draw = 25, advance = -1.0, rootCapture = -2, rootCheck = -4, rootQuiet = 5, rootCastle = 10 },
	Fischer = { arch = "N", gambit = 50, dev = 1.1, simplify = 1.0, mob = 1.1, atkFor = 1.1, atkAgainst = 1.0, shield = 1.0, struct = 1.1, passed = 1.2, draw = -10, advance = 0.3, rootCapture = 2, rootCheck = 0, rootQuiet = 0, rootCastle = 4 },
	Kasparov = { arch = "A", gambit = 90, dev = 1.2, simplify = 0.7, mob = 1.4, atkFor = 1.5, atkAgainst = 0.9, shield = 0.9, struct = 1.0, passed = 1.2, draw = -30, advance = 0.8, rootCapture = 4, rootCheck = 6, rootQuiet = 0, rootCastle = 2 },
	Karpov = { arch = "P", gambit = 20, dev = 1.0, simplify = 1.2, mob = 1.2, atkFor = 0.7, atkAgainst = 1.2, shield = 1.2, struct = 1.5, passed = 1.1, draw = 10, advance = -0.5, rootCapture = 0, rootCheck = -2, rootQuiet = 4, rootCastle = 6 },
	Carlsen = { arch = "N", gambit = 40, dev = 1.0, simplify = 1.3, mob = 1.0, atkFor = 1.0, atkAgainst = 1.0, shield = 1.1, struct = 1.2, passed = 1.4, draw = -15, advance = 0.2, rootCapture = 0, rootCheck = 0, rootQuiet = 2, rootCastle = 4 },
	Capablanca = { arch = "P", gambit = 20, dev = 1.1, simplify = 1.6, mob = 1.0, atkFor = 0.8, atkAgainst = 1.0, shield = 1.1, struct = 1.2, passed = 1.3, draw = 0, advance = 0, rootCapture = 1, rootCheck = -2, rootQuiet = 3, rootCastle = 6 },
	Morphy = { arch = "A", gambit = 150, dev = 2.0, simplify = 0.6, mob = 1.3, atkFor = 1.6, atkAgainst = 0.8, shield = 0.8, struct = 0.9, passed = 1.0, draw = -30, advance = 0.6, rootCapture = 5, rootCheck = 8, rootQuiet = 0, rootCastle = 8 },
	Alien = { arch = "A", gambit = 280, dev = 1.2, simplify = 0.4, mob = 1.3, atkFor = 1.9, atkAgainst = 0.7, shield = 0.6, struct = 0.8, passed = 1.1, draw = -45, advance = 1.2, rootCapture = 9, rootCheck = 11, rootQuiet = -1, rootCastle = 0 },
}
-- personality, not strength: every evaluation weight is pulled 70% of the way back to neutral, so a
-- style changes preferences (book, tie-breaks, draw attitude) without distorting the evaluation
for name, p in pairs(STYLE_PARAMS) do
	if name ~= "Normal" then
		for _, k in ipairs({ "mob", "atkFor", "atkAgainst", "shield", "struct", "passed", "simplify", "dev" }) do
			p[k] = 1 + (p[k] - 1) * 0.3
		end
		p.draw = p.draw * 0.4
		p.advance = p.advance * 0.3
	end
end
Claude1.STYLES = { "Normal", "Aggressive", "Defensive", "Passive", "Tal", "Petrosian", "Fischer", "Kasparov", "Karpov", "Carlsen", "Capablanca", "Morphy", "Alien" }
Claude1.STYLE_INFO = {
	Normal = "Balanced play that adapts to the position.",
	Aggressive = "Attacks, tactics and checkmates first.",
	Defensive = "King safety, solid structure, counterplay.",
	Passive = "Low risk, positional stability.",
	Tal = "Mikhail Tal: sacrifices and wild attacks, loves gambits.",
	Petrosian = "Tigran Petrosian: prophylaxis and an iron-solid defence.",
	Fischer = "Bobby Fischer: clear plans, precise technique, 1.e4.",
	Kasparov = "Garry Kasparov: dynamic initiative and active pieces.",
	Karpov = "Anatoly Karpov: quiet positional squeeze.",
	Carlsen = "Magnus Carlsen: universal, grinds out small edges.",
	Capablanca = "Jose Capablanca: simple, clear, trades into winning endgames.",
	Morphy = "Paul Morphy: rapid development and open attacking play.",
	Alien = "Gambit hunter: Alien and Martian gambits, sharp attacks.",
}
local style = STYLE_PARAMS.Normal
local styleName = "Normal"
local rootSide = 1
local drawBase = 0

------------------------------------------------------------------------------------------------
-- evaluation
------------------------------------------------------------------------------------------------
local wPawnCnt, bPawnCnt, wMinR, bMaxR = {}, {}, {}, {}
for i = 1, 12 do
	wPawnCnt[i], bPawnCnt[i], wMinR[i], bMaxR[i] = 0, 0, 8, -1
end
local zoneStamp = 0
local zoneW, zoneB = {}, {} -- squares around the white / black king
for i = 1, 120 do
	zoneW[i], zoneB[i] = 0, 0
end
local PASSED_BONUS = { 0, 6, 12, 24, 44, 76, 120, 0 } -- by relative rank (index = rank + 1)
local MOB_N, MOB_B, MOB_R, MOB_Q = 4, 3, 2, 1
local ATK_UNIT = { 0, 2, 2, 3, 5, 0 }
local attackBoost = 1.35
local THREAT = { [2] = 18, [3] = 18, [4] = 30, [5] = 40 }
local LAZY = 260

local function kdist(a, b)
	local dr = (a - 22) // 10 - (b - 22) // 10
	local df = (a - 22) % 10 - (b - 22) % 10
	if dr < 0 then dr = -dr end
	if df < 0 then df = -df end
	return (dr > df) and dr or df
end

local function centerDist(sq)
	local r = (sq - 22) // 10
	local f = (sq - 22) % 10
	return ((r <= 3) and (3 - r) or (r - 4)) + ((f <= 3) and (3 - f) or (f - 4))
end

local function dynamicTerms()
	local pawnCntW, pawnCntB, minW, maxB = wPawnCnt, bPawnCnt, wMinR, bMaxR
	for i = 1, 12 do
		pawnCntW[i], pawnCntB[i], minW[i], maxB[i] = 0, 0, 8, -1
	end
	zoneStamp = zoneStamp + 1
	local stamp = zoneStamp
	-- king zones
	do
		local k = kingSq1
		zoneW[k] = stamp
		for i = 1, 8 do zoneW[k + KG[i]] = stamp end
		zoneW[k + 20] = stamp
		zoneW[k + 19] = stamp
		zoneW[k + 21] = stamp
		k = kingSq2
		zoneB[k] = stamp
		for i = 1, 8 do zoneB[k + KG[i]] = stamp end
		zoneB[k - 20] = stamp
		zoneB[k - 19] = stamp
		zoneB[k - 21] = stamp
	end

	local dmg, deg = 0, 0
	local wBishops, bBishops = 0, 0
	local wMinor, bMinor, wHeavy, bHeavy, pawns = 0, 0, 0, 0, 0
	local pawnsW, pawnsB = 0, 0
	local wPC0, wPC1, bPC0, bPC1 = 0, 0, 0, 0 -- own pawns on dark(0)/light(1) squares
	local wBishopCol, bBishopCol = -1, -1
	local atkUnitsW, atkCntW, atkUnitsB, atkCntB = 0, 0, 0, 0
	local mobMul = style.mob

	-- pass 1: pawn files
	for c = 1, 2 do
		local plist = PLS[c]
		for li = 1, PLNUM[c] do
			local sq0 = plist[li]
			local p = board[sq0]
			local r = (sq0 - 22) // 10
			local f = (sq0 - 22) % 10
			if p == 1 then
				pawnCntW[f + 2] = pawnCntW[f + 2] + 1
				if r < minW[f + 2] then minW[f + 2] = r end
				pawns = pawns + 1
				pawnsW = pawnsW + 1
				if (r + f) % 2 == 0 then wPC0 = wPC0 + 1 else wPC1 = wPC1 + 1 end
			elseif p == 9 then
				pawnCntB[f + 2] = pawnCntB[f + 2] + 1
				if r > maxB[f + 2] then maxB[f + 2] = r end
				pawns = pawns + 1
				pawnsB = pawnsB + 1
				if (r + f) % 2 == 0 then bPC0 = bPC0 + 1 else bPC1 = bPC1 + 1 end
			end
		end
	end

	-- pass 2: pieces
	for c = 1, 2 do
		local plist = PLS[c]
		for li = 1, PLNUM[c] do
			local sq = plist[li]
			local r = (sq - 22) // 10
			local f = (sq - 22) % 10
			local p = board[sq]
			if p ~= 0 then
				local t = PTYPE[p]
				-- a minor/major piece attacked by an enemy pawn is in real danger
				if t >= 2 and t <= 5 then
					if p < 9 then
						if board[sq + 9] == 9 or board[sq + 11] == 9 then
							dmg = dmg - THREAT[t]
							deg = deg - THREAT[t]
						end
					elseif board[sq - 9] == 1 or board[sq - 11] == 1 then
						dmg = dmg + THREAT[t]
						deg = deg + THREAT[t]
					end
				end
				if p < 9 then
					-- ---------------- white piece ----------------
					if t == 1 then
						local passed = (maxB[f + 1] <= r) and (maxB[f + 2] <= r) and (maxB[f + 3] <= r)
						if passed then
							local b = PASSED_BONUS[r + 1] * style.passed
							if board[sq + 10] ~= 0 then b = b * 0.5 end
							dmg = dmg + b // 2
							deg = deg + b
							if r >= 2 then
								local ps = 92 + f
								deg = deg + (kdist(kingSq2, ps) - kdist(kingSq1, ps)) * (r - 1) * 2
							end
						end
						if pawnCntW[f + 2] > 1 then
							dmg = dmg - 8 * style.struct
							deg = deg - 14 * style.struct
						end
						if pawnCntW[f + 1] == 0 and pawnCntW[f + 3] == 0 then
							dmg = dmg - 10 * style.struct
							deg = deg - 16 * style.struct
						end
						if board[sq - 1] == 1 or board[sq + 1] == 1 or board[sq - 9] == 1 or board[sq - 11] == 1 then
							local b = (3 + r * 2) * style.struct
							dmg = dmg + b
							deg = deg + b
						end
						if style.advance ~= 0 then
							dmg = dmg + r * style.advance
						end
					elseif t == 2 then
						wMinor = wMinor + 1
						local cnt, zh = 0, 0
						for i = 1, 8 do
							local s = sq + KN[i]
							local tp = board[s]
							if tp == 0 or (tp ~= 16 and PCOL[tp] == 2) then
								cnt = cnt + 1
								if zoneB[s] == stamp then zh = zh + 1 end
							end
						end
						local b = (cnt - 4) * MOB_N * mobMul
						dmg = dmg + b
						deg = deg + b
						if r >= 3 and r <= 5 and (board[sq - 9] == 1 or board[sq - 11] == 1)
							and maxB[f + 1] <= r and maxB[f + 3] <= r then
							dmg = dmg + 20 * style.struct
							deg = deg + 10 * style.struct
						end
						if zh > 0 then atkUnitsW = atkUnitsW + ATK_UNIT[2]; atkCntW = atkCntW + 1 end
					elseif t == 3 or t == 4 or t == 5 then
						local cnt, zh = 0, 0
						if t ~= 4 then
							for i = 1, 4 do
								local d = BDIR[i]
								local s = sq + d
								local tp = board[s]
								while tp == 0 do
									cnt = cnt + 1
									if zoneB[s] == stamp then zh = zh + 1 end
									s = s + d
									tp = board[s]
								end
								if tp ~= 16 and PCOL[tp] == 2 then
									cnt = cnt + 1
									if zoneB[s] == stamp then zh = zh + 1 end
								end
							end
						end
						if t ~= 3 then
							for i = 1, 4 do
								local d = RDIR[i]
								local s = sq + d
								local tp = board[s]
								while tp == 0 do
									cnt = cnt + 1
									if zoneB[s] == stamp then zh = zh + 1 end
									s = s + d
									tp = board[s]
								end
								if tp ~= 16 and PCOL[tp] == 2 then
									cnt = cnt + 1
									if zoneB[s] == stamp then zh = zh + 1 end
								end
							end
						end
						if t == 3 then
							wBishops = wBishops + 1
							wMinor = wMinor + 1
							wBishopCol = (r + f) % 2
							local same = (wBishopCol == 0) and wPC0 or wPC1
							local b = (cnt - 6) * MOB_B * mobMul
							if same > 3 then b = b - (same - 3) * 3 * style.struct end
							dmg = dmg + b
							deg = deg + b
						elseif t == 4 then
							wHeavy = wHeavy + 1
							dmg = dmg + (cnt - 6) * MOB_R * mobMul
							deg = deg + (cnt - 6) * 2 * MOB_R * mobMul
							if pawnCntW[f + 2] == 0 then
								if pawnCntB[f + 2] == 0 then
									dmg = dmg + 22
									deg = deg + 12
								else
									dmg = dmg + 10
									deg = deg + 8
								end
							end
							if r == 6 then
								dmg = dmg + 14
								deg = deg + 22
							end
						else
							wHeavy = wHeavy + 1
							local b = (cnt - 13) * MOB_Q * mobMul
							dmg = dmg + b
							deg = deg + b
						end
						if zh > 0 then atkUnitsW = atkUnitsW + ATK_UNIT[t]; atkCntW = atkCntW + 1 end
					end
				else
					-- ---------------- black piece ----------------
					if t == 1 then
						local passed = (minW[f + 1] >= r) and (minW[f + 2] >= r) and (minW[f + 3] >= r)
						if passed then
							local b = PASSED_BONUS[8 - r] * style.passed
							if board[sq - 10] ~= 0 then b = b * 0.5 end
							dmg = dmg - b // 2
							deg = deg - b
							if r <= 5 then
								local ps = 22 + f
								deg = deg - (kdist(kingSq1, ps) - kdist(kingSq2, ps)) * (6 - r) * 2
							end
						end
						if pawnCntB[f + 2] > 1 then
							dmg = dmg + 8 * style.struct
							deg = deg + 14 * style.struct
						end
						if pawnCntB[f + 1] == 0 and pawnCntB[f + 3] == 0 then
							dmg = dmg + 10 * style.struct
							deg = deg + 16 * style.struct
						end
						if board[sq - 1] == 9 or board[sq + 1] == 9 or board[sq + 9] == 9 or board[sq + 11] == 9 then
							local b = (3 + (7 - r) * 2) * style.struct
							dmg = dmg - b
							deg = deg - b
						end
						if style.advance ~= 0 then
							dmg = dmg - (7 - r) * style.advance
						end
					elseif t == 2 then
						bMinor = bMinor + 1
						local cnt, zh = 0, 0
						for i = 1, 8 do
							local s = sq + KN[i]
							local tp = board[s]
							if tp == 0 or (tp ~= 16 and PCOL[tp] == 1) then
								cnt = cnt + 1
								if zoneW[s] == stamp then zh = zh + 1 end
							end
						end
						local b = (cnt - 4) * MOB_N * mobMul
						dmg = dmg - b
						deg = deg - b
						if r >= 2 and r <= 4 and (board[sq + 9] == 9 or board[sq + 11] == 9)
							and minW[f + 1] >= r and minW[f + 3] >= r then
							dmg = dmg - 20 * style.struct
							deg = deg - 10 * style.struct
						end
						if zh > 0 then atkUnitsB = atkUnitsB + ATK_UNIT[2]; atkCntB = atkCntB + 1 end
					elseif t == 3 or t == 4 or t == 5 then
						local cnt, zh = 0, 0
						if t ~= 4 then
							for i = 1, 4 do
								local d = BDIR[i]
								local s = sq + d
								local tp = board[s]
								while tp == 0 do
									cnt = cnt + 1
									if zoneW[s] == stamp then zh = zh + 1 end
									s = s + d
									tp = board[s]
								end
								if tp ~= 16 and PCOL[tp] == 1 then
									cnt = cnt + 1
									if zoneW[s] == stamp then zh = zh + 1 end
								end
							end
						end
						if t ~= 3 then
							for i = 1, 4 do
								local d = RDIR[i]
								local s = sq + d
								local tp = board[s]
								while tp == 0 do
									cnt = cnt + 1
									if zoneW[s] == stamp then zh = zh + 1 end
									s = s + d
									tp = board[s]
								end
								if tp ~= 16 and PCOL[tp] == 1 then
									cnt = cnt + 1
									if zoneW[s] == stamp then zh = zh + 1 end
								end
							end
						end
						if t == 3 then
							bBishops = bBishops + 1
							bMinor = bMinor + 1
							bBishopCol = (r + f) % 2
							local same = (bBishopCol == 0) and bPC0 or bPC1
							local b = (cnt - 6) * MOB_B * mobMul
							if same > 3 then b = b - (same - 3) * 3 * style.struct end
							dmg = dmg - b
							deg = deg - b
						elseif t == 4 then
							bHeavy = bHeavy + 1
							dmg = dmg - (cnt - 6) * MOB_R * mobMul
							deg = deg - (cnt - 6) * 2 * MOB_R * mobMul
							if pawnCntB[f + 2] == 0 then
								if pawnCntW[f + 2] == 0 then
									dmg = dmg - 22
									deg = deg - 12
								else
									dmg = dmg - 10
									deg = deg - 8
								end
							end
							if r == 1 then
								dmg = dmg - 14
								deg = deg - 22
							end
						else
							bHeavy = bHeavy + 1
							local b = (cnt - 13) * MOB_Q * mobMul
							dmg = dmg - b
							deg = deg - b
						end
						if zh > 0 then atkUnitsB = atkUnitsB + ATK_UNIT[t]; atkCntB = atkCntB + 1 end
					end
				end
			end
		end
	end

	-- insufficient material -> dead draw
	if pawns == 0 and wHeavy == 0 and bHeavy == 0 and wMinor <= 1 and bMinor <= 1 then
		return nil
	end

	-- development: minor pieces still on their start squares (fades out with the game phase)
	do
		local devW = (board[23] == 2 and 1 or 0) + (board[28] == 2 and 1 or 0)
			+ (board[24] == 3 and 1 or 0) + (board[27] == 3 and 1 or 0)
		local devB = (board[93] == 10 and 1 or 0) + (board[98] == 10 and 1 or 0)
			+ (board[94] == 11 and 1 or 0) + (board[97] == 11 and 1 or 0)
		dmg = dmg - (devW - devB) * 9 * style.dev
		if qsq1 ~= 25 and qsq1 ~= 0 and devW >= 2 then dmg = dmg - 14 end
		if qsq2 ~= 95 and qsq2 ~= 0 and devB >= 2 then dmg = dmg + 14 end
	end

	-- mop-up: drive a lone king to the edge and bring the winning king close
	if pawnsB == 0 and bHeavy == 0 and bMinor == 0 and (wHeavy * 5 + wMinor * 3) >= 5 then
		local bonus = 12 * centerDist(kingSq2) + 6 * (7 - kdist(kingSq1, kingSq2))
		dmg = dmg + bonus
		deg = deg + bonus
	elseif pawnsW == 0 and wHeavy == 0 and wMinor == 0 and (bHeavy * 5 + bMinor * 3) >= 5 then
		local bonus = 12 * centerDist(kingSq1) + 6 * (7 - kdist(kingSq1, kingSq2))
		dmg = dmg - bonus
		deg = deg - bonus
	end

	-- opposite-coloured bishops (and nothing else but pawns) are drawish
	local scale = 1
	if wBishops == 1 and bBishops == 1 and wMinor == 1 and bMinor == 1 and wHeavy == 0 and bHeavy == 0
		and wBishopCol ~= bBishopCol then
		scale = 0.55
	end

	if wBishops >= 2 then dmg = dmg + 28; deg = deg + 48 end
	if bBishops >= 2 then dmg = dmg - 28; deg = deg - 48 end

	-- king safety: attack zone danger
	local factorOnBlack = (rootSide == 1) and style.atkFor or style.atkAgainst -- white attacking black king
	local factorOnWhite = (rootSide == 2) and style.atkFor or style.atkAgainst
	if atkCntW >= 2 then
		local danger = atkUnitsW * (atkUnitsW + 2 * atkCntW) // 3
		danger = danger * attackBoost
		if danger > 540 then danger = 540 end
		dmg = dmg + danger * factorOnBlack
	end
	if atkCntB >= 2 then
		local danger = atkUnitsB * (atkUnitsB + 2 * atkCntB) // 3
		danger = danger * attackBoost
		if danger > 540 then danger = 540 end
		dmg = dmg - danger * factorOnWhite
	end

	-- king safety: pawn shield (middlegame only)
	do
		local k = kingSq1
		local r = (k - 22) // 10
		if r <= 2 then
			local sh = 0
			for d = -1, 1 do
				local s1 = k + 10 + d
				local s2 = k + 20 + d
				if board[s1] ~= 16 then
					if board[s1] == 1 then
						sh = sh + 12
					elseif board[s2] == 1 then
						sh = sh + 6
					else
						sh = sh - 14
					end
					local fi = (s1 - 22) % 10
					if fi >= 0 and fi <= 7 and pawnCntW[fi + 2] == 0 and pawnCntB[fi + 2] == 0 then
						sh = sh - 12
					end
				end
			end
			dmg = dmg + sh * ((rootSide == 1) and style.shield or 1.0)
		end
		k = kingSq2
		r = (k - 22) // 10
		if r >= 5 then
			local sh = 0
			for d = -1, 1 do
				local s1 = k - 10 + d
				local s2 = k - 20 + d
				if board[s1] ~= 16 then
					if board[s1] == 9 then
						sh = sh + 12
					elseif board[s2] == 9 then
						sh = sh + 6
					else
						sh = sh - 14
					end
					local fi = (s1 - 22) % 10
					if fi >= 0 and fi <= 7 and pawnCntW[fi + 2] == 0 and pawnCntB[fi + 2] == 0 then
						sh = sh - 12
					end
				end
			end
			dmg = dmg - sh * ((rootSide == 2) and style.shield or 1.0)
		end
	end

	return dmg, deg, scale
end

-- cache of dynamic evaluation terms keyed by position hash (valid for one search: style/root side fixed)
local EV_SIZE = 65536
local evKey, evMg, evEg, evSc, evStamp = {}, {}, {}, {}, {}
for i = 1, EV_SIZE do
	evKey[i], evMg[i], evEg[i], evSc[i], evStamp[i] = 0, 0, 0, 1, 0
end
local evGen = 1

-- white-centric total from the incremental score plus the dynamic terms
local function whiteTotal(dmg, deg, scale)
	local ph = phase
	if ph > 24 then ph = 24 end
	local total = ((mgS + dmg) * ph + (egS + deg) * (24 - ph)) // 24
	if scale ~= 1 then
		total = total * scale // 1
	end
	-- the side that is clearly ahead gains by trading down; the side that is behind loses by it
	if total > 150 or total < -150 then
		local bonus = (24 - ph) * 1.5 * style.simplify
		if total > 0 then
			total = total + bonus
		else
			total = total - bonus
		end
	end
	return total // 1
end

-- evaluation from the side-to-move's point of view
local function evaluate(alpha, beta)
	local ph = phase
	if ph > 24 then ph = 24 end
	local base = (mgS * ph + egS * (24 - ph)) // 24
	local sc = (side == 1) and base or -base
	if sc - LAZY >= beta or sc + LAZY <= alpha then
		return sc
	end
	local slot = h1 % EV_SIZE + 1
	local dmg, deg, scale
	if evStamp[slot] == evGen and evKey[slot] == h2 then
		dmg, deg, scale = evMg[slot], evEg[slot], evSc[slot]
		if dmg == nil then
			return 0
		end
	else
		dmg, deg, scale = dynamicTerms()
		evStamp[slot], evKey[slot] = evGen, h2
		evMg[slot], evEg[slot], evSc[slot] = dmg, deg, scale
		if not dmg then
			return 0
		end
	end
	local total = whiteTotal(dmg, deg, scale)
	if side == 1 then
		return total + 10
	end
	return -total + 10
end


------------------------------------------------------------------------------------------------
-- search state
------------------------------------------------------------------------------------------------
local TT_SIZE = 262144
local ttKey, ttMove, ttScore, ttDepth, ttFlag = {}, {}, {}, {}, {}
for i = 1, TT_SIZE do
	ttKey[i], ttMove[i], ttScore[i], ttDepth[i], ttFlag[i] = 0, 0, 0, -1, 0
end

local MV = {}
local MSC = {}
local PV = {}
local PVLEN = {}
for i = 0, MAXPLY + 2 do
	MV[i], MSC[i], PV[i], PVLEN[i] = {}, {}, {}, 0
end
local KILLER1, KILLER2 = {}, {}
for i = 0, MAXPLY + 2 do
	KILLER1[i], KILLER2[i] = 0, 0
end
local HISTORY = {}
for i = 0, 32767 do
	HISTORY[i] = 0
end
local LMR = {}
for d = 1, 64 do
	LMR[d] = {}
	for m = 1, 64 do
		LMR[d][m] = floor(0.6 + math.log(d) * math.log(m) / 2.4)
	end
end

local nodes = 0
local stopFlag = false
local deadline = 0
local yieldFn, cancelFn
local yieldEvery = 0.012
local yieldMin, yieldMax = 0.010, 0.028
local nextYield = 0
local searchStart = 0
local selDepth = 0

local lastBeat = 0

local function checkLimits()
	local now = clock()
	lastBeat = now
	if now >= deadline then
		stopFlag = true
		return
	end
	if cancelFn and cancelFn() then
		stopFlag = true
		return
	end
	if yieldFn and now >= nextYield then
		local waited = yieldFn()
		-- aim for ~70% of each frame being search: slice = 2.2 x the time a frame costs without us
		if type(waited) == "number" and waited > 0 then
			local slice = waited * 2.2
			if slice < yieldMin then slice = yieldMin elseif slice > yieldMax then slice = yieldMax end
			yieldEvery = slice
		end
		nextYield = clock() + yieldEvery
		if cancelFn and cancelFn() then
			stopFlag = true
		end
	end
end

local function drawValue()
	-- value (for the side to move) of a drawn position
	if side == rootSide then
		return drawBase
	end
	return -drawBase
end

local function isRepetition()
	local limit = sp - half
	if limit < 1 then limit = 1 end
	local i = sp - 2
	while i >= limit do
		if posH1[i] == h1 and posH2[i] == h2 then
			return true
		end
		i = i - 2
	end
	return false
end

-- scoring moves for ordering ------------------------------------------------------------------
local SEVAL = {}
for i = 0, MAXPLY + 4 do
	SEVAL[i] = -INF
end
local ttGen = {}
for i = 1, TT_SIZE do
	ttGen[i] = 0
end
local ttGeneration = 1

local T = { -- search tuning constants (one table: the engine is close to Lua's 200-locals limit)
	LMR_DIV = 2.4, LMR_BASE = 0.6, RFP = 90, RFP_DEPTH = 6,
	FUT_BASE = 100, FUT_STEP = 90, FUT_DEPTH = 4, LMP_BASE = 3, LMP_DEPTH = 4,
	NMP_BASE = 3, NMP_DIV = 4, NMP_MIN = 3, ASP = 18, SEE_PRUNE = 80, DELTA = 200,
}
local FEAT = { qchecks = false, razor = false, improving = false, singular = false, lmrhist = false, notimprovingLMR = false, sacsafe = true, matethreat = true, queenthreat = true }
Claude1.FEAT = FEAT
function Claude1.tune(p)
	if p.lmrDiv then T.LMR_DIV = p.lmrDiv end
	if p.lmrBase then T.LMR_BASE = p.lmrBase end
	if p.rfp then T.RFP = p.rfp end
	if p.rfpDepth then T.RFP_DEPTH = p.rfpDepth end
	if p.futBase then T.FUT_BASE = p.futBase end
	if p.futStep then T.FUT_STEP = p.futStep end
	if p.futDepth then T.FUT_DEPTH = p.futDepth end
	if p.lmpBase then T.LMP_BASE = p.lmpBase end
	if p.lmpDepth then T.LMP_DEPTH = p.lmpDepth end
	if p.nmpBase then T.NMP_BASE = p.nmpBase end
	if p.nmpDiv then T.NMP_DIV = p.nmpDiv end
	if p.nmpMin then T.NMP_MIN = p.nmpMin end
	if p.asp then T.ASP = p.asp end
	if p.seePrune then T.SEE_PRUNE = p.seePrune end
	if p.delta then T.DELTA = p.delta end
	for d = 1, 64 do
		for m = 1, 64 do
			LMR[d][m] = floor(T.LMR_BASE + math.log(d) * math.log(m) / T.LMR_DIV)
		end
	end
end

local COUNTER = {}
for i = 0, 2047 do
	COUNTER[i] = 0
end
local MOVEAT, PIECEAT = {}, {}
for i = 0, MAXPLY + 2 do
	MOVEAT[i], PIECEAT[i] = 0, 0
end

-- move scoring for ordering ------------------------------------------------------------------
local function scoreMoves(list, scores, n, ttm, ply, cm)
	local k1, k2 = KILLER1[ply], KILLER2[ply]
	local hbase = (side == 1) and 0 or 16384
	for i = 1, n do
		local m = list[i]
		local from = m % 128
		local rest = m // 128
		local to = rest % 128
		rest = rest // 128
		local promo = rest % 8
		local flag = rest // 8
		local sc
		if m == ttm then
			sc = 10000000
		else
			local victim = board[to]
			if victim ~= 0 or flag == 2 then
				local vt = (flag == 2) and 1 or PTYPE[victim]
				local at = PTYPE[board[from]]
				if vt >= at then
					sc = 2000000 + vt * 16 - at
				else
					local s = see(m)
					if s >= 0 then
						sc = 2000000 + vt * 16 - at
					else
						sc = -1000000 + s
					end
				end
				if promo == 5 then sc = sc + 500000 end
			elseif promo ~= 0 then
				sc = (promo == 5) and 1900000 or -500000
			elseif m == k1 then
				sc = 1500000
			elseif m == k2 then
				sc = 1400000
			elseif m == cm then
				sc = 1300000
			else
				sc = HISTORY[hbase + from * 128 + to]
				if flag >= 3 then sc = sc + 300 end
			end
		end
		scores[i] = sc
	end
end

local function pickMove(list, scores, n, i)
	local best = i
	local bs = scores[i]
	for j = i + 1, n do
		if scores[j] > bs then
			bs = scores[j]
			best = j
		end
	end
	if best ~= i then
		list[i], list[best] = list[best], list[i]
		scores[i], scores[best] = scores[best], scores[i]
	end
	return list[i]
end

local VALUE_PIECE = { 100, 320, 330, 500, 900, 0 }

-- material + piece-square only (incremental): used for pruning decisions at interior nodes
local function evalFast()
	local ph = phase
	if ph > 24 then ph = 24 end
	local base = (mgS * ph + egS * (24 - ph)) // 24
	if side == 1 then
		return base + 10
	end
	return -base + 10
end

local function ttStoreScore(score, ply)
	if score > MATE_BOUND then
		return score + ply
	elseif score < -MATE_BOUND then
		return score - ply
	end
	return score
end

local function ttLoadScore(score, ply)
	if score > MATE_BOUND then
		return score - ply
	elseif score < -MATE_BOUND then
		return score + ply
	end
	return score
end

------------------------------------------------------------------------------------------------
-- cheap "does the move just made give check?" (direct + discovered), replaces a full attack scan
------------------------------------------------------------------------------------------------
-- called AFTER makeMove: board is updated and `side` is already the opponent; us = the mover
local function givesCheckAfter(from, to, flag, us)
	local ek = (us == 1) and kingSq2 or kingSq1
	if flag >= 2 then
		return isAttacked(ek, us) -- castling / en passant: rare, use the full test
	end
	local pt = PTYPE[board[to]]
	if pt == 1 then
		if us == 1 then
			if to + 9 == ek or to + 11 == ek then return true end
		elseif to - 9 == ek or to - 11 == ek then
			return true
		end
	elseif pt == 2 then
		local d = ek - to
		if d == 21 or d == 19 or d == 12 or d == 8 or d == -8 or d == -12 or d == -19 or d == -21 then
			return true
		end
	end
	local own = (us == 1) and 0 or 8
	local bishop, rook, queen = own + 3, own + 4, own + 5
	local row = RAYDIR[ek]
	local step = row[to]
	if step ~= 0 then
		local sq = ek + step
		local q = board[sq]
		while q == 0 do
			sq = sq + step
			q = board[sq]
		end
		if step == 1 or step == -1 or step == 10 or step == -10 then
			if q == rook or q == queen then return true end
		elseif q == bishop or q == queen then
			return true
		end
	end
	step = row[from]
	if step ~= 0 then
		local sq = ek + step
		local q = board[sq]
		while q == 0 do
			sq = sq + step
			q = board[sq]
		end
		if step == 1 or step == -1 or step == 10 or step == -10 then
			if q == rook or q == queen then return true end
		elseif q == bishop or q == queen then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------------------
-- quiescence search
------------------------------------------------------------------------------------------------
local function qsearch(alpha, beta, ply, chk, qd)
	nodes = nodes + 1
	if nodes % 256 == 0 then
		checkLimits()
	end
	if stopFlag then
		return 0
	end
	if ply >= MAXPLY then
		return evaluate(alpha, beta)
	end
	if half >= 100 or isRepetition() then
		return drawValue()
	end

	-- transposition table (entries from the main search are always deeper than a quiescence node)
	local idx = h1 % TT_SIZE + 1
	local ttm = 0
	if ttKey[idx] == h2 then
		local fl = ttFlag[idx]
		local sc = ttLoadScore(ttScore[idx], ply)
		if fl == 1 or (fl == 2 and sc >= beta) or (fl == 3 and sc <= alpha) then
			return sc
		end
		ttm = ttMove[idx]
	end

	local incheck = chk
	if incheck == nil then
		incheck = inCheck()
	end
	local origAlpha = alpha
	local stand = -INF
	if not incheck then
		stand = evaluate(alpha, beta)
		if stand >= beta then
			return stand
		end
		if stand > alpha then
			alpha = stand
		end
	end

	local list, scores = MV[ply], MSC[ply]
	local n = generate(list, not incheck)
	for i = 1, n do
		local m = list[i]
		local from = m % 128
		local rest = m // 128
		local to = rest % 128
		rest = rest // 128
		local promo = rest % 8
		local flag = rest // 8
		local victim = board[to]
		local sc = 0
		if m == ttm then
			sc = 100000
		elseif victim ~= 0 then
			sc = PTYPE[victim] * 16 - PTYPE[board[from]] + 1000
		elseif flag == 2 then
			sc = 1000 + 16 - 1
		end
		if promo == 5 then sc = sc + 900 end
		scores[i] = sc
	end

	local legal = 0
	local best = stand
	local bestMove = 0
	for i = 1, n do
		local m = pickMove(list, scores, n, i)
		local from = m % 128
		local rest = m // 128
		local to = rest % 128
		rest = rest // 128
		local promo = rest % 8
		local flag = rest // 8
		local skipMove = false
		if not incheck then
			local victim = board[to]
			local gain = 0
			if victim ~= 0 then
				gain = VALUE_PIECE[PTYPE[victim]]
			elseif flag == 2 then
				gain = 100
			end
			if promo == 5 then gain = gain + 800 end
			local nearKing = false
			if FEAT.sacsafe and qd <= 1 then
				local eks = (side == 1) and kingSq2 or kingSq1
				nearKing = kdist(to, eks) <= 2
			end
			if stand + gain + T.DELTA <= alpha and promo == 0 and not nearKing then
				skipMove = true -- delta pruning
			elseif victim ~= 0 and PTYPE[victim] < PTYPE[board[from]] and see(m) < 0 and not nearKing then
				skipMove = true -- losing capture
			end
		end
		if not skipMove and makeMove(m, incheck) then
			legal = legal + 1
			local score = -qsearch(-beta, -alpha, ply + 1, givesCheckAfter(from, to, flag, 3 - side), qd + 1)
			unmakeMove(m)
			if stopFlag then
				return 0
			end
			if score > best then
				best = score
				bestMove = m
				if score > alpha then
					alpha = score
					if score >= beta then
						if ttKey[idx] ~= h2 or ttDepth[idx] <= 0 then
							ttKey[idx], ttMove[idx], ttScore[idx], ttDepth[idx], ttFlag[idx] = h2, m, ttStoreScore(score, ply), 0, 2
						end
						return score
					end
				end
			end
		end
	end
	if incheck and legal == 0 then
		return -(MATE - ply)
	end

	-- first quiescence ply: also try quiet checking moves that do not hang the piece
	-- (finds forcing tactics a plain capture search cannot see)
	if FEAT.qchecks and qd == 0 and not incheck and best < beta and stand + 250 >= alpha and ply < MAXPLY - 4 then
		local n2 = generate(list, false)
		for i = 1, n2 do
			local m = list[i]
			local rest = m // 128
			local to = rest % 128
			rest = rest // 128
			local promo = rest % 8
			local flag = rest // 8
			if board[to] == 0 and promo == 0 and flag ~= 2 then
				local qfrom = m % 128
				if makeMove(m, false) then
					if givesCheckAfter(qfrom, to, flag, 3 - side) then
						unmakeMove(m)
						if see(m) >= 0 and makeMove(m, false) then
							local score = -qsearch(-beta, -alpha, ply + 1, true, 1)
							unmakeMove(m)
							if stopFlag then
								return 0
							end
							if score > best then
								best = score
								if score > alpha then
									alpha = score
									if score >= beta then
										return score
									end
								end
							end
						end
					else
						unmakeMove(m)
					end
				end
			end
		end
	end

	if ttKey[idx] ~= h2 or ttDepth[idx] <= 0 then
		local fl = (best > origAlpha) and 1 or 3
		ttKey[idx], ttMove[idx], ttScore[idx], ttDepth[idx], ttFlag[idx] = h2, bestMove, ttStoreScore(best, ply), 0, fl
	end
	return best
end

------------------------------------------------------------------------------------------------
-- main search
------------------------------------------------------------------------------------------------
local function search(depth, alpha, beta, ply, isPV, canNull, chk, excl)
	PVLEN[ply] = 0
	if depth <= 0 then
		return qsearch(alpha, beta, ply, chk, 0)
	end
	nodes = nodes + 1
	if nodes % 256 == 0 then
		checkLimits()
	end
	if stopFlag then
		return 0
	end
	if ply > selDepth then
		selDepth = ply
	end

	local rootNode = (ply == 0)
	if not rootNode then
		if half >= 100 or isRepetition() then
			return drawValue()
		end
		if ply >= MAXPLY then
			return evaluate(alpha, beta)
		end
		-- mate distance pruning
		local mateAlpha = -(MATE - ply)
		if mateAlpha > alpha then alpha = mateAlpha end
		local mateBeta = MATE - ply - 1
		if mateBeta < beta then beta = mateBeta end
		if alpha >= beta then
			return alpha
		end
	end

	local incheck = chk
	if incheck == nil then
		incheck = inCheck()
	end
	if incheck then
		depth = depth + 1
	end

	-- hunted-queen extension: when our queen is attacked by a cheaper piece we must react, so these
	-- lines are searched one ply deeper (this exposes queen traps that a shallow search misses)
	if FEAT.queenthreat and not incheck and ply < 48 and not excl then
		local qs = (side == 1) and qsq1 or qsq2
		if qs ~= 0 and board[qs] == ((side == 1) and 5 or 13) then
			local attacker = leastAttacker(qs, 3 - side)
			if attacker ~= 0 and PTYPE[board[attacker]] < 5 then
				depth = depth + 1
			end
		end
	end

	-- transposition table
	local idx = h1 % TT_SIZE + 1
	local ttm = 0
	local tthit = false
	local ttscore, ttdepth, ttflag = 0, -1, 0
	if ttKey[idx] == h2 then
		tthit = true
		ttm = ttMove[idx]
		ttscore = ttLoadScore(ttScore[idx], ply)
		ttdepth = ttDepth[idx]
		ttflag = ttFlag[idx]
		if ttdepth >= depth and not isPV and not excl then
			if ttflag == 1 then
				return ttscore
			elseif ttflag == 2 and ttscore >= beta then
				return ttscore
			elseif ttflag == 3 and ttscore <= alpha then
				return ttscore
			end
		end
	end

	local staticEval = -INF
	if not incheck then
		staticEval = evalFast()
		if tthit and ttdepth >= 0 then
			if (ttflag == 1) or (ttflag == 2 and ttscore > staticEval) or (ttflag == 3 and ttscore < staticEval) then
				staticEval = ttscore
			end
		end
	end
	SEVAL[ply] = staticEval
	local improving = FEAT.improving and (not incheck) and ply >= 2 and SEVAL[ply - 2] ~= -INF and staticEval > SEVAL[ply - 2]

	if not isPV and not incheck and not excl then
		-- razoring: hopeless at the horizon, confirm with a capture search
		if FEAT.razor and depth <= 2 and staticEval + 260 + 120 * (depth - 1) <= alpha then
			local q = qsearch(alpha, beta, ply, false, 0)
			if q <= alpha then
				return q
			end
		end
		-- reverse futility (static null move)
		local rfpMargin = (improving and (T.RFP - 15) or T.RFP) * depth
		if depth <= T.RFP_DEPTH and staticEval - rfpMargin >= beta and staticEval < MATE_BOUND then
			return staticEval - rfpMargin
		end
		-- null move
		if canNull and depth >= T.NMP_MIN and staticEval >= beta and ((side == 1) and npm1 or npm2) > 0 then
			local R = T.NMP_BASE + depth // T.NMP_DIV + ((staticEval - beta) > 200 and 1 or 0)
			MOVEAT[ply], PIECEAT[ply] = 0, 0
			makeNull()
			local score = -search(depth - 1 - R, -beta, -beta + 1, ply + 1, false, false, false)
			unmakeNull()
			if stopFlag then
				return 0
			end
			if score >= beta then
				if score > MATE_BOUND then
					score = beta
				end
				return score
			end
			if FEAT.matethreat and score < -MATE_BOUND then
				depth = depth + 1 -- passing loses to a mate threat: calculate this node deeper
			end
		end
	end

	-- internal iterative reduction
	if depth >= 4 and ttm == 0 and not incheck then
		depth = depth - 1
	end

	-- counter move
	local cmIdx, cm = 0, 0
	if ply >= 1 and PIECEAT[ply - 1] ~= 0 then
		cmIdx = PIECEAT[ply - 1] * 128 + (MOVEAT[ply - 1] // 128) % 128
		cm = COUNTER[cmIdx]
	end

	-- singular extension: if the TT move is far better than every alternative, search it deeper
	local singular = false
	if FEAT.singular and not excl and depth >= 8 and ttm ~= 0 and tthit and ttdepth >= depth - 3 and ttflag ~= 3
		and abs(ttscore) < MATE_BOUND and not rootNode then
		local sBeta = ttscore - 2 * depth
		local sc = search((depth - 1) // 2, sBeta - 1, sBeta, ply, false, false, incheck, ttm)
		if stopFlag then
			return 0
		end
		if sc < sBeta then
			singular = true
		end
	end

	local list, scores = MV[ply], MSC[ply]
	local n = generate(list, false)
	scoreMoves(list, scores, n, ttm, ply, cm)

	local origAlpha = alpha
	local bestScore = -INF
	local bestMove = 0
	local legal = 0
	local quietsTried = 0
	local quiets = nil

	for i = 1, n do
		local m = pickMove(list, scores, n, i)
		local from = m % 128
		local rest = m // 128
		local to = rest % 128
		rest = rest // 128
		local promo = rest % 8
		local flag = rest // 8
		local isCapture = (board[to] ~= 0) or flag == 2
		local isQuiet = (not isCapture) and promo == 0

		-- prune clearly losing captures at shallow depth (never the only move searched)
		local pruneCapture = legal > 0 and not isPV and not incheck and depth <= 3 and scores[i] < -900000
			and scores[i] + 1000000 < -T.SEE_PRUNE * depth
		if pruneCapture and FEAT.sacsafe then
			-- a capture next to the enemy king may be a sacrifice that starts an attack: keep it
			local eks = (side == 1) and kingSq2 or kingSq1
			if kdist(to, eks) <= 2 then
				pruneCapture = false
			end
		end

		if m ~= excl and not pruneCapture and makeMove(m, incheck) then
			legal = legal + 1
			local givesCheck = givesCheckAfter(from, to, flag, 3 - side)
			local newDepth = depth - 1
			if singular and m == ttm then
				newDepth = newDepth + 1
			end
			local skip = false

			local attackingMove = false
			if FEAT.sacsafe and isQuiet then
				local eks = (side == 2) and kingSq2 or kingSq1 -- side already flipped: the mover attacks the other king
				attackingMove = kdist(to, eks) <= 2
			end
			if not isPV and not incheck and isQuiet and givesCheck == false and not attackingMove and bestScore > -MATE_BOUND then
				if depth <= T.LMP_DEPTH and legal > T.LMP_BASE + depth * depth + (improving and depth * depth // 2 or 0) then
					skip = true -- late move pruning
				elseif depth <= T.FUT_DEPTH and staticEval + T.FUT_BASE + T.FUT_STEP * depth <= alpha then
					skip = true -- futility pruning
				end
			end

			if skip then
				unmakeMove(m)
			else
				MOVEAT[ply] = m
				PIECEAT[ply] = board[to]
				local score
				if legal == 1 then
					score = -search(newDepth, -beta, -alpha, ply + 1, isPV, true, givesCheck)
				else
					local reduction = 0
					if depth >= 3 and legal > 3 and isQuiet and not incheck and givesCheck == false then
						local dd = depth > 63 and 63 or depth
						local mm = legal > 63 and 63 or legal
						reduction = LMR[dd][mm]
						if isPV then reduction = reduction - 1 end
						if m == KILLER1[ply] or m == KILLER2[ply] or m == cm then reduction = reduction - 1 end
						if FEAT.notimprovingLMR and not improving then reduction = reduction + 1 end
						if FEAT.lmrhist then
							local hv = HISTORY[((3 - side == 1) and 0 or 16384) + from * 128 + to]
							if hv > 6000 then
								reduction = reduction - 1
							elseif hv < -3000 then
								reduction = reduction + 1
							end
						end
						if reduction < 0 then reduction = 0 end
						if reduction > newDepth - 1 then reduction = newDepth - 1 end
						if reduction < 0 then reduction = 0 end
					end
					score = -search(newDepth - reduction, -alpha - 1, -alpha, ply + 1, false, true, givesCheck)
					if score > alpha and reduction > 0 then
						score = -search(newDepth, -alpha - 1, -alpha, ply + 1, false, true, givesCheck)
					end
					if score > alpha and score < beta and isPV then
						score = -search(newDepth, -beta, -alpha, ply + 1, true, true, givesCheck)
					end
				end
				unmakeMove(m)
				if stopFlag then
					return 0
				end

				if isQuiet and score <= alpha then
					quietsTried = quietsTried + 1
					if not quiets then quiets = {} end
					quiets[quietsTried] = m
				end

				if score > bestScore then
					bestScore = score
					bestMove = m
					if score > alpha then
						alpha = score
						local pvn = PV[ply]
						pvn[1] = m
						local child = PV[ply + 1]
						local cl = PVLEN[ply + 1]
						for j = 1, cl do
							pvn[j + 1] = child[j]
						end
						PVLEN[ply] = cl + 1
						if score >= beta then
							if isQuiet then
								if KILLER1[ply] ~= m then
									KILLER2[ply] = KILLER1[ply]
									KILLER1[ply] = m
								end
								if cmIdx ~= 0 then
									COUNTER[cmIdx] = m
								end
								local hbase = (3 - side == 1) and 0 or 16384
								local bonus = depth * depth
								if bonus > 400 then bonus = 400 end
								local hi = hbase + from * 128 + to
								local v = HISTORY[hi] + bonus
								if v > 16000 then v = 16000 end
								HISTORY[hi] = v
								for j = 1, quietsTried do
									local qm = quiets[j]
									local qf = qm % 128
									local qt = (qm // 128) % 128
									local qi = hbase + qf * 128 + qt
									local qv = HISTORY[qi] - bonus
									if qv < -16000 then qv = -16000 end
									HISTORY[qi] = qv
								end
							end
							break
						end
					end
				end
			end
		end
	end

	if legal == 0 then
		if excl then
			return alpha -- the excluded move was the only one: counts as "singular"
		end
		if incheck then
			return -(MATE - ply)
		end
		return drawValue()
	end
	if bestScore == -INF then
		return staticEval ~= -INF and staticEval or 0
	end
	if excl then
		return bestScore
	end

	local flag
	if bestScore >= beta then
		flag = 2
	elseif bestScore > origAlpha then
		flag = 1
	else
		flag = 3
	end
	if ttdepth <= depth or ttKey[idx] ~= h2 or ttGen[idx] ~= ttGeneration then
		ttKey[idx] = h2
		ttMove[idx] = bestMove
		ttScore[idx] = ttStoreScore(bestScore, ply)
		ttDepth[idx] = depth
		ttFlag[idx] = flag
		ttGen[idx] = ttGeneration
	end
	return bestScore
end

------------------------------------------------------------------------------------------------
-- opening book: {uci, weight, tags} per position. Tags: A/D/P/N archetypes, G = gambit,
-- player names and "Alien" mark lines a style prefers.  The book is only a suggestion: the search
-- scores the book move and the engine ignores it when its own evaluation disagrees.
------------------------------------------------------------------------------------------------
local BOOK = {
["2105153330_3423950716"]={{"e2e4",77,"A,D,P,N,G,Tal,Petrosian,Fischer,Kasparov,Karpov,Carlsen,Capablanca,Morphy,Alien",""},{"d2d4",31,"A,D,P,N,G,Tal,Petrosian,Fischer,Kasparov,Karpov,Carlsen,Capablanca,Morphy",""},{"c2c4",3,"P,N,Karpov,Carlsen",""},{"g1f3",2,"P,N,Fischer,Carlsen,Capablanca",""},{"f2f4",1,"A",""},{"b2b3",1,"N",""}},
["684420154_3972914460"]={{"e7e5",33,"A,D,P,N,G,Tal,Petrosian,Fischer,Karpov,Carlsen,Capablanca,Morphy",""},{"c7c5",16,"A,D,P,N,G,Tal,Petrosian,Fischer,Kasparov,Karpov",""},{"e7e6",5,"A,P,N,Fischer,Kasparov,Karpov",""},{"c7c6",15,"A,D,P,N,G,Tal,Petrosian,Karpov,Alien",""},{"d7d5",2,"A,N",""},{"d7d6",3,"A,D,Petrosian,Kasparov",""},{"g7g6",1,"N",""},{"g8f6",1,"A",""},{"b8c6",1,"N",""}},
["3253743854_979365912"]={{"g1f3",24,"A,D,P,N,G,Tal,Petrosian,Fischer,Karpov,Carlsen,Capablanca,Morphy",""},{"b1c3",2,"A,N,G",""},{"f2f4",4,"A,G,Tal,Morphy","King's Gambit"},{"d2d4",2,"A,G,Tal,Morphy","Danish Gambit"},{"f1c4",1,"P",""}},
["1463094049_1014714665"]={{"b8c6",21,"A,D,P,N,G,Tal,Petrosian,Fischer,Karpov,Carlsen,Capablanca,Morphy",""},{"g8f6",2,"A,D,G,Petrosian,Carlsen",""},{"d7d6",1,"N",""}},
["408951392_2125392182"]={{"f1b5",10,"A,D,P,N,G,Tal,Petrosian,Fischer,Karpov,Carlsen,Capablanca",""},{"f1c4",5,"A,P,G,Tal,Karpov,Carlsen,Morphy",""},{"d2d4",3,"A,N,G,Morphy",""},{"b1c3",2,"N",""},{"c2c3",1,"N",""}},
["1771541017_3779789203"]={{"a7a6",5,"A,P,N,G,Tal,Fischer,Karpov,Capablanca",""},{"g8f6",3,"D,P,N,Petrosian,Carlsen",""},{"f7f5",1,"A,G,Tal",""},{"d7d6",1,"A",""}},
["978157378_554420112"]={{"b5a4",4,"A,N,G,Tal,Fischer,Karpov,Capablanca",""},{"b5c6",1,"P,Fischer",""}},
["1535189885_2184785354"]={{"g8f6",4,"A,N,G,Tal,Fischer,Karpov,Capablanca",""}},
["2950282901_2573271184"]={{"e1g1",4,"A,N,G,Tal,Fischer,Karpov,Capablanca",""}},
["1215707678_1770130692"]={{"f8e7",3,"A,N,G,Tal,Fischer,Karpov,Capablanca",""},{"f6e4",1,"N",""}},
["564414734_3091100876"]={{"f1e1",3,"A,N,G,Tal,Fischer,Karpov,Capablanca",""}},
["1733487666_1614977624"]={{"b7b5",3,"A,N,G,Tal,Fischer,Karpov,Capablanca",""}},
["1468498599_1572149390"]={{"a4b3",3,"A,N,G,Tal,Fischer,Karpov,Capablanca",""}},
["2596708996_2622929967"]={{"d7d6",2,"N,Fischer,Karpov,Capablanca",""},{"e8g8",1,"A,G,Tal",""}},
["1966156715_1489506985"]={{"c2c3",2,"N,Fischer,Karpov,Capablanca",""}},
["3998564817_2340888102"]={{"e8g8",2,"N,Fischer,Karpov,Capablanca",""}},
["491200994_3591943871"]={{"h2h3",2,"N,Fischer,Karpov,Capablanca",""}},
["3574630371_2021402549"]={{"c6a5",1,"N,Fischer,Karpov,Capablanca",""},{"c6b8",1,"N,Karpov",""}},
["4277888928_3555392071"]={{"b3c2",1,"N,Fischer,Karpov,Capablanca",""}},
["2144763308_3155629629"]={{"c7c5",1,"N,Fischer,Karpov,Capablanca",""}},
["295095992_3228891544"]={{"d2d4",1,"N,Fischer,Karpov,Capablanca",""}},
["206463857_3290713921"]={{"d8c7",1,"N,Fischer,Karpov,Capablanca",""}},
["2588251810_984194986"]={{"d2d4",1,"N,Karpov",""}},
["2275228523_1056516467"]={{"b8d7",1,"N,Karpov",""}},
["657862284_3189514271"]={{"b1d2",1,"N,Karpov",""}},
["4228528192_3679378913"]={{"c8b7",1,"N,Karpov",""}},
["1775551159_3251180726"]={{"c2c3",1,"A,G,Tal",""}},
["4071663821_310777913"]={{"d7d5",1,"A,G,Tal",""}},
["3615956343_2970946307"]={{"e4d5",1,"A,G,Tal",""}},
["3397653860_1295949680"]={{"f6d5",1,"A,G,Tal",""}},
["955523926_793321017"]={{"f3e5",1,"A,G,Tal",""}},
["2449118928_2805866304"]={{"c6e5",1,"A,G,Tal",""}},
["1461824584_935018140"]={{"e1e5",1,"A,G,Tal",""}},
["888020167_430336252"]={{"c7c6",1,"A,G,Tal",""}},
["1928331501_794733307"]={{"d2d3",1,"A,G,Tal",""}},
["230252057_3912747428"]={{"e7d6",1,"A,G,Tal",""}},
["2647592945_4195560649"]={{"e1g1",2,"D,N,Petrosian,Carlsen",""},{"d2d3",1,"P",""}},
["2053147514_183509341"]={{"f6e4",1,"D,Petrosian,Carlsen",""},{"f8c5",1,"N",""}},
["3978868815_3188035263"]={{"d2d4",1,"D,Petrosian,Carlsen",""}},
["4042265990_3126147174"]={{"e4d6",1,"D,Petrosian,Carlsen",""}},
["375256893_3220860768"]={{"b5c6",1,"D,Petrosian,Carlsen",""}},
["3232205192_54835491"]={{"d7c6",1,"D,Petrosian,Carlsen",""}},
["2657070559_392920461"]={{"d4e5",1,"D,Petrosian,Carlsen",""}},
["1175289867_933231277"]={{"d6f5",1,"D,Petrosian,Carlsen",""}},
["4155089628_3183093637"]={{"d1d8",1,"D,Petrosian,Carlsen",""}},
["193422607_66594076"]={{"e8d8",1,"D,Petrosian,Carlsen",""}},
["3971416567_2645889491"]={{"d7c6",1,"P,Fischer",""}},
["2991531424_2308625789"]={{"e1g1",1,"P,Fischer",""}},
["1440784683_2038028521"]={{"f7f6",1,"P,Fischer",""}},
["143199881_39812741"]={{"d2d4",1,"P,Fischer",""}},
["357671744_101697628"]={{"e5d4",1,"P,Fischer",""}},
["500872505_617324647"]={{"f3d4",1,"P,Fischer",""}},
["4111456717_3371803670"]={{"c6c5",1,"P,Fischer",""}},
["1100199038_3566309872"]={{"d4b3",1,"P,Fischer",""}},
["1624204788_38132300"]={{"d8d1",1,"P,Fischer",""}},
["304217470_2622184601"]={{"f1d1",1,"P,Fischer",""}},
["3226991920_3251485640"]={{"c8e6",1,"P,Fischer",""}},
["3745384747_3715605222"]={{"d2d4",1,"N",""}},
["3269895394_3643216959"]={{"b7b5",1,"N",""}},
["4063480439_3838875369"]={{"a4b3",1,"N",""}},
["1064495700_624112200"]={{"d7d5",1,"N",""}},
["440754158_2258641266"]={{"d4e5",1,"N",""}},
["3256316474_2790565458"]={{"c8e6",1,"N",""}},
["3551888371_447844566"]={{"b1d2",1,"N",""}},
["143234367_2145611048"]={{"f8c5",1,"N",""}},
["2858601199_2497002864"]={{"c2c3",1,"N",""}},
["2326852144_169980203"]={{"b1c3",1,"A,G,Tal",""}},
["1587121158_2352351946"]={{"f5e4",1,"A,G,Tal",""}},
["527974280_162482764"]={{"c3e4",1,"A,G,Tal",""}},
["3181594810_1110982368"]={{"d7d5",1,"A,G,Tal",""}},
["2559900928_3786091994"]={{"e4g3",1,"A,G,Tal",""}},
["3800453381_1014648726"]={{"f8c5",1,"P",""}},
["1080889045_3612090318"]={{"c2c3",1,"P",""}},
["3674825903_67310401"]={{"e8g8",1,"P",""}},
["1799820382_2958985144"]={{"e1g1",1,"P",""}},
["3484712983_2843719244"]={{"d7d6",1,"P",""}},
["2254445366_634760981"]={{"d2d4",1,"A",""}},
["2612573951_562371020"]={{"c8d7",1,"A",""}},
["4207699456_3079142854"]={{"b1c3",1,"A",""}},
["786765878_831538727"]={{"g8f6",1,"A",""}},
["3669853662_717777789"]={{"b5c6",1,"A",""}},
["206044011_2524364094"]={{"d7c6",1,"A",""}},
["3742101464_4243024544"]={{"d1d3",1,"A",""}},
["3948080526_1787668767"]={{"e5d4",1,"A",""}},
["3822713847_1212793124"]={{"f3d4",1,"A",""}},
["3633042602_3787878661"]={{"c2c3",1,"N",""}},
["1139785424_847871370"]={{"e8g8",1,"N",""}},
["2969427683_1863767315"]={{"d2d4",1,"N",""}},
["2904912682_1799775178"]={{"c5b6",1,"N",""}},
["3507801193_1537264773"]={{"d4e5",1,"N",""}},
["155640253_2069121957"]={{"f6e4",1,"N",""}},
["1165319123_803657300"]={{"f8c5",2,"A,P,G,Tal,Karpov,Carlsen,Morphy",""},{"g8f6",3,"A,G,Tal,Morphy",""}},
["3885892611_3302000140"]={{"c2c3",1,"P,Karpov,Carlsen",""},{"b2b4",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2096787065_396331651"]={{"g8f6",1,"P,Karpov,Carlsen",""}},
["2292380561_214411225"]={{"d2d3",1,"P,Karpov,Carlsen",""}},
["4159417701_3400451206"]={{"d7d6",1,"P,Karpov,Carlsen",""}},
["404497482_238053888"]={{"e1g1",1,"P,Karpov,Carlsen",""}},
["4289962177_4275267476"]={{"e8g8",1,"P,Karpov,Carlsen",""}},
["211927282_2739719949"]={{"f1e1",1,"P,Karpov,Carlsen",""}},
["1247241678_2066751897"]={{"a7a6",1,"P,Karpov,Carlsen",""}},
["428705941_3144738714"]={{"c4b3",1,"P,Karpov,Carlsen",""}},
["86048718_1107257058"]={{"c8e6",1,"P,Karpov,Carlsen",""}},
["344067591_4246360166"]={{"b1d2",1,"P,Karpov,Carlsen",""}},
["2130741743_2845212881"]={{"c5b4",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2009969739_3922864585"]={{"c2c3",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["3970555441_983377222"]={{"b4a5",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["3028510911_3943197397"]={{"d2d4",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2841363830_4015578124"]={{"e5d4",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2714817295_3449599031"]={{"e1g1",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["1182750596_1031780771"]={{"d4d3",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2995402786_1145986629"]={{"d1b3",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["1665976543_2965236596"]={{"d8f6",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["338282614_2311373381"]={{"e4e5",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["395942743_3130936558"]={{"f6g6",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2595330649_2527541796"]={{"c1a3",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["1975332879_2754315249"]={{"g8e7",1,"A,G,Tal,Morphy","Italian Game: Evans Gambit"}},
["2972567099_884931342"]={{"d2d4",1,"A",""},{"f3g5",2,"A,G,Tal,Morphy",""}},
["2901765106_820923863"]={{"e5d4",1,"A",""}},
["2759753099_304752108"]={{"e1g1",1,"A",""}},
["1137834240_3804833912"]={{"f6e4",1,"A",""}},
["3566848565_1446807450"]={{"f1e1",1,"A",""}},
["2456776457_2386585870"]={{"d7d5",1,"A",""}},
["3076053683_768834100"]={{"c4d5",1,"A",""}},
["3846388178_3445499182"]={{"d8d5",1,"A",""}},
["90859912_1127414021"]={{"b1c3",1,"A",""}},
["3510835134_3307553508"]={{"d5a5",1,"A",""}},
["1163715901_3869118912"]={{"d7d5",2,"A,G,Tal,Morphy",""}},
["1617645703_1158480634"]={{"e4d5",2,"A,G,Tal,Morphy",""}},
["2103990420_3106313865"]={{"f6d5",1,"A,G,Tal,Morphy",""},{"c6a5",1,"A",""}},
["2400743078_3679524800"]={{"g5f7",1,"A,G,Tal,Morphy",""}},
["1860498650_4286992453"]={{"e8f7",1,"A,G,Tal,Morphy",""}},
["1131725050_3054912687"]={{"d1f3",1,"A,G,Tal,Morphy",""}},
["26948349_2672853759"]={{"f7e6",1,"A,G,Tal,Morphy",""}},
["616797138_2173102414"]={{"b1c3",1,"A,G,Tal,Morphy",""}},
["4041928164_126964399"]={{"c6b4",1,"A,G,Tal,Morphy",""}},
["3305824193_1084532664"]={{"f3e4",1,"A,G,Tal,Morphy",""}},
["24409299_1914976164"]={{"c7c6",1,"A,G,Tal,Morphy",""}},
["1198156025_1155331491"]={{"a2a3",1,"A,G,Tal,Morphy",""}},
["824909897_4050088408"]={{"b4a6",1,"A,G,Tal,Morphy",""}},
["2979695885_3880845072"]={{"d2d4",1,"A,G,Tal,Morphy",""}},
["1451473111_313543547"]={{"c4b5",1,"A",""}},
["3869488016_2330887416"]={{"c7c6",1,"A",""}},
["2696785850_3155576575"]={{"d5c6",1,"A",""}},
["2155531639_3814486589"]={{"b7c6",1,"A",""}},
["583588607_192143540"]={{"b5e2",1,"A",""}},
["110033702_3835735475"]={{"h7h6",1,"A",""}},
["1109504973_4284290497"]={{"g5f3",1,"A",""}},
["3058733259_763232015"]={{"e5e4",1,"A",""}},
["2661456336_2122783900"]={{"f3e5",1,"A",""}},
["2631003691_2207189633"]={{"f8d6",1,"A",""}},
["95991721_2063491055"]={{"e5d4",3,"A,N,G,Morphy","Scotch Gambit"}},
["221487568_1480210388"]={{"f3d4",2,"N",""},{"f1c4",1,"A,G,Morphy","Scotch Gambit"}},
["3857108260_3020436389"]={{"g8f6",1,"N",""},{"f8c5",1,"N",""}},
["297685196_2941263615"]={{"d4c6",1,"N",""}},
["3721559118_3643103491"]={{"b7c6",1,"N",""}},
["4197053141_1242901868"]={{"e4e5",1,"N",""}},
["4187595252_2035262407"]={{"d8e7",1,"N",""}},
["3946182469_4000499915"]={{"d1e2",1,"N",""}},
["2913902687_1292561709"]={{"f6d5",1,"N",""}},
["1242483029_4154472487"]={{"c2c4",1,"N",""}},
["1113861170_1000601507"]={{"c8a6",1,"N",""}},
["473367599_1793184950"]={{"b2b3",1,"N",""}},
["1775913466_1011230856"]={{"g7g6",1,"N",""}},
["1192071924_1597924349"]={{"c1e3",1,"N",""}},
["2687852778_2301425982"]={{"d8f6",1,"N",""}},
["3612368963_2958413839"]={{"c2c3",1,"N",""}},
["1278478905_1662704768"]={{"g8e7",1,"N",""}},
["969319238_1483515825"]={{"f1c4",1,"N",""}},
["1691607797_153393363"]={{"c6e5",1,"N",""}},
["469145827_3585674838"]={{"c4e2",1,"N",""}},
["324169968_4106720406"]={{"f6g6",1,"N",""}},
["1344725091_158468278"]={{"f8c5",1,"A,G,Morphy","Scotch Gambit"}},
["4073570227_3796130030"]={{"e1g1",1,"A,G,Morphy","Scotch Gambit"}},
["358759224_312956282"]={{"d7d6",1,"A,G,Morphy","Scotch Gambit"}},
["4204114455_3594124284"]={{"c2c3",1,"A,G,Morphy","Scotch Gambit"}},
["1643239533_91682675"]={{"c8e6",1,"A,G,Morphy","Scotch Gambit"}},
["1884498340_3113468407"]={{"c4e6",1,"A,G,Morphy","Scotch Gambit"}},
["3346092496_1143982549"]={{"f7e6",1,"A,G,Morphy","Scotch Gambit"}},
["3932144020_1606704354"]={{"c3d4",1,"A,G,Morphy","Scotch Gambit"}},
["1593660117_1616287814"]={{"c5b6",1,"A,G,Morphy","Scotch Gambit"}},
["3427361878_4172894935"]={{"g8f6",2,"N",""}},
["940702142_3823206285"]={{"f1b5",1,"N",""},{"d2d4",1,"N",""}},
["1239839175_2080675624"]={{"f8b4",1,"N",""}},
["2650176742_523775923"]={{"e1g1",1,"N",""}},
["2052716653_4024115751"]={{"e8g8",1,"N",""}},
["2303432798_2990836414"]={{"d2d3",1,"N",""}},
["4127377066_1949166049"]={{"d7d6",1,"N",""}},
["435507077_2964539239"]={{"c1g5",1,"N",""}},
["1585752920_3054902095"]={{"b4c3",1,"N",""}},
["785817419_1523563348"]={{"b2c3",1,"N",""}},
["1103114120_3255877520"]={{"d8e7",1,"N",""}},
["1399617849_1429066908"]={{"f1e1",1,"N",""}},
["362470405_2370910728"]={{"c6d8",1,"N",""}},
["1409963297_3412145334"]={{"d3d4",1,"N",""}},
["2857985169_1605106036"]={{"d8e6",1,"N",""}},
["633951351_3887188308"]={{"e5d4",1,"N",""}},
["759317006_3312820591"]={{"f3d4",1,"N",""}},
["3315019514_692561182"]={{"f8b4",1,"N",""}},
["294069211_1249582469"]={{"d4c6",1,"N",""}},
["3723169625_1007573625"]={{"b7c6",1,"N",""}},
["4195385794_2940087830"]={{"f1d3",1,"N",""}},
["620637535_3420586837"]={{"d7d5",1,"N",""}},
["29989093_1752240239"]={{"e4d5",1,"N",""}},
["483037430_2488960028"]={{"c6d5",1,"N",""}},
["844358611_2333948967"]={{"e1g1",1,"N",""}},
["3590088536_2080256435"]={{"e8g8",1,"N",""}},
["653133675_643930410"]={{"c1g5",1,"N",""}},
["1637868470_549766402"]={{"c7c6",1,"N",""}},
["2741868233_656637043"]={{"f3e5",2,"A,D,G,Petrosian,Carlsen",""}},
["174269263_2941549834"]={{"d7d6",2,"A,D,G,Petrosian,Carlsen","Petrov's Defence: Cochrane Gambit"}},
["3851725408_1808454540"]={{"e5f3",1,"D,Petrosian,Carlsen",""},{"e5f7",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["3890732443_2529346961"]={{"f6e4",1,"D,Petrosian,Carlsen",""}},
["1890578094_574057075"]={{"d2d4",1,"D,Petrosian,Carlsen",""}},
["1836532583_644340906"]={{"d6d5",1,"D,Petrosian,Carlsen",""}},
["997571967_395934034"]={{"f1d3",1,"D,Petrosian,Carlsen",""}},
["3852145122_1933923345"]={{"f8d6",1,"D,Petrosian,Carlsen",""}},
["2353742044_1850141812"]={{"e1g1",1,"D,Petrosian,Carlsen",""}},
["1810154583_2661671392"]={{"e8g8",1,"D,Petrosian,Carlsen",""}},
["2566300772_3275377017"]={{"c2c4",1,"D,Petrosian,Carlsen",""}},
["2426159363_255428349"]={{"c7c6",1,"D,Petrosian,Carlsen",""}},
["3598867753_968967418"]={{"b1c3",1,"D,Petrosian,Carlsen",""}},
["44770079_3218538267"]={{"e4c3",1,"D,Petrosian,Carlsen",""}},
["558417065_40038567"]={{"b2c3",1,"D,Petrosian,Carlsen",""}},
["975316267_2926065512"]={{"d5c4",1,"D,Petrosian,Carlsen",""}},
["818581760_1069461205"]={{"d3c2",1,"D,Petrosian,Carlsen",""}},
["4067058913_1614112986"]={{"e8f7",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["3757723841_698711088"]={{"d2d4",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["3257072904_771082985"]={{"f6e4",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["1433062973_2566939915"]={{"f1d3",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["2340709024_4259072072"]={{"d6d5",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["3716586680_3424841136"]={{"e1g1",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["2037713137_3573800004"]={{"f8e7",1,"A,G","Petrov's Defence: Cochrane Gambit"}},
["3099755022_4175822767"]={{"d2d4",1,"N",""}},
["2769956807_4239739254"]={{"g8f6",1,"N",""}},
["1363325487_3891094572"]={{"b1c3",1,"N",""}},
["2238434329_1643831245"]={{"b8d7",1,"N",""}},
["633395710_3776960161"]={{"f1c4",1,"N",""}},
["2027264077_2958551491"]={{"f8e7",1,"N",""}},
["285731677_1642827787"]={{"e1g1",1,"N",""}},
["4138233814_2433260959"]={{"e8g8",1,"N",""}},
["96079845_3432461574"]={{"d1e2",1,"N",""}},
["1126258943_1877938400"]={{"c7c6",1,"N",""}},
["88032469_1494733543"]={{"a2a4",1,"N",""}},
["366563032_3158854649"]={{"g8f6",2,"A,N,G",""}},
["3783381808_2802869923"]={{"g2g3",1,"N",""},{"f2f4",1,"A,G","Vienna Gambit"}},
["3263629582_1467859837"]={{"d7d5",1,"N",""}},
["3887119540_4109291591"]={{"e4d5",1,"N",""}},
["4206081191_147145780"]={{"f6d5",1,"N",""}},
["147030677_1790100861"]={{"f1g2",1,"N",""}},
["2764148308_878960369"]={{"d5b6",1,"N",""}},
["1145638838_3527430217"]={{"g1e2",1,"N",""}},
["2275966168_2387878113"]={{"b8c6",1,"N",""}},
["3372051865_3431045374"]={{"d2d3",1,"N",""}},
["3082040173_183040929"]={{"f8e7",1,"N",""}},
["3731243133_3679748713"]={{"e1g1",1,"N",""}},
["969524470_733450237"]={{"e8g8",1,"N",""}},
["4107142094_2722949941"]={{"d7d5",1,"A,G","Vienna Gambit"}},
["3522803316_31455247"]={{"f4e5",1,"A,G","Vienna Gambit"}},
["2644735585_2659898646"]={{"f6e4",1,"A,G","Vienna Gambit"}},
["183190868_712997620"]={{"g1f3",1,"A,G","Vienna Gambit"}},
["2620292763_744217541"]={{"f8e7",1,"A,G","Vienna Gambit"}},
["4126936459_4259815949"]={{"d2d4",1,"A,G","Vienna Gambit"}},
["3894714434_4189525204"]={{"e8g8",1,"A,G","Vienna Gambit"}},
["1483395251_1307213869"]={{"f1d3",1,"A,G","Vienna Gambit"}},
["2256829486_691449198"]={{"f7f5",1,"A,G","Vienna Gambit"}},
["415259277_1638898661"]={{"e5f6",1,"A,G","Vienna Gambit"}},
["2581526084_2782719023"]={{"e7f6",1,"A,G","Vienna Gambit"}},
["4274443574_2824923078"]={{"e1g1",1,"A,G","Vienna Gambit"}},
["3569344528_1057193358"]={{"e5f4",2,"A,G,Tal,Morphy","King's Gambit"},{"f8c5",1,"A",""},{"d7d5",1,"A,G","King's Gambit"}},
["2984907375_2270624828"]={{"g1f3",2,"A,G,Tal,Morphy","King's Gambit Accepted"}},
["657402272_2171755789"]={{"g7g5",2,"A,G,Tal,Morphy","King's Gambit Accepted"}},
["598085746_3568055398"]={{"h2h4",1,"A,G,Tal,Morphy","King's Gambit Accepted"},{"f1c4",1,"A,G,Tal","King's Gambit Accepted"}},
["1373586636_2442499471"]={{"g5g4",1,"A,G,Tal,Morphy","King's Gambit Accepted"}},
["2467185101_1036928662"]={{"f3e5",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["2440902198_3234222219"]={{"g8f6",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["1696967646_3684597201"]={{"f1c4",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["942729837_2329297587"]={{"d7d5",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["487022551_692408713"]={{"e4d5",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["284612_3580806650"]={{"f8d6",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["1775503098_3362618783"]={{"d2d4",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["1946987315_3426601798"]={{"f6h5",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["1216026572_2060636973"]={{"b1c3",1,"A,G,Tal,Morphy","King's Gambit: Kieseritzky Gambit"}},
["2125681089_2246314756"]={{"g5g4",1,"A,G,Tal","King's Gambit Accepted"}},
["3160560832_700438557"]={{"e1g1",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["1540214859_3646739849"]={{"g4f3",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["3617797380_2440977701"]={{"d1f3",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["946793377_1179491500"]={{"d8f6",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["1326181128_2134160797"]={{"e4e5",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["1287370793_1282292534"]={{"f6e5",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["2133496676_2240199975"]={{"c4f7",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["3659667498_3183838105"]={{"e8f7",1,"A,G,Tal","King's Gambit: Muzio Gambit"}},
["1985265600_3560254934"]={{"g1f3",1,"A",""}},
["3767632911_3524365543"]={{"d7d6",1,"A",""}},
["258346272_378479201"]={{"b1c3",1,"A",""}},
["3679417110_2425919872"]={{"g8f6",1,"A",""}},
["790097662_2344662234"]={{"f1c4",1,"A",""}},
["1912778573_3666381752"]={{"b8c6",1,"A",""}},
["1029160460_2556244903"]={{"d2d3",1,"A",""}},
["1109319928_1580486904"]={{"c8g4",1,"A",""}},
["4052243882_2626711220"]={{"e4d5",1,"A,G","Falkbeer Counter Gambit"}},
["3968556473_1622932167"]={{"e5e4",1,"A,G","Falkbeer Counter Gambit"}},
["3296285858_859904340"]={{"d2d3",1,"A,G","Falkbeer Counter Gambit"}},
["3140487766_4113070603"]={{"g8f6",1,"A,G","Falkbeer Counter Gambit"}},
["1332254654_4000339793"]={{"d3e4",1,"A,G","Falkbeer Counter Gambit"}},
["3739816813_1813866703"]={{"f6e4",1,"A,G","Falkbeer Counter Gambit"}},
["1235296344_3639133997"]={{"g1f3",1,"A,G","Falkbeer Counter Gambit"}},
["3747879831_3737937436"]={{"f8c5",1,"A,G","Falkbeer Counter Gambit"}},
["2106541127_905590340"]={{"d1e2",1,"A,G","Falkbeer Counter Gambit"}},
["991171421_2525107106"]={{"d8e7",1,"A,G","Falkbeer Counter Gambit"}},
["699942380_29325486"]={{"c1d2",1,"A,G","Falkbeer Counter Gambit"}},
["1103596304_2753542914"]={{"e4d2",1,"A,G","Falkbeer Counter Gambit"}},
["3702691390_1087844740"]={{"b1d2",1,"A,G","Falkbeer Counter Gambit"}},
["3032047928_2338030487"]={{"b8c6",1,"A,G","Falkbeer Counter Gambit"}},
["4226576505_3381541768"]={{"d2b3",1,"A,G","Falkbeer Counter Gambit"}},
["3693649191_1041188545"]={{"e5d4",2,"A,G,Tal,Morphy","Danish Gambit"}},
["3567487838_483077882"]={{"c2c3",1,"A,G,Tal,Morphy","Danish Gambit"},{"d1d4",1,"A,Morphy",""}},
["1338499364_3481543285"]={{"d4c3",1,"A,G,Tal,Morphy","Danish Gambit"}},
["2173679549_2558372897"]={{"f1c4",1,"A,G,Tal,Morphy","Danish Gambit"}},
["3701143054_3375731523"]={{"c3b2",1,"A,G,Tal,Morphy","Danish Gambit"}},
["1527795581_218564162"]={{"c1b2",1,"A,G,Tal,Morphy","Danish Gambit"}},
["3500085894_1798748097"]={{"d7d5",1,"A,G,Tal,Morphy","Danish Gambit"}},
["4121470780_3366298875"]={{"c4d5",1,"A,G,Tal,Morphy","Danish Gambit"}},
["2813543517_673774561"]={{"g8f6",1,"A,G,Tal,Morphy","Danish Gambit"}},
["1407965621_863033019"]={{"d5f7",1,"A,G,Tal,Morphy","Danish Gambit"}},
["195942228_2577854743"]={{"e8f7",1,"A,G,Tal,Morphy","Danish Gambit"}},
["3304124008_4270709814"]={{"d1d8",1,"A,G,Tal,Morphy","Danish Gambit"}},
["954083771_1087364783"]={{"f8b4",1,"A,G,Tal,Morphy","Danish Gambit"}},
["2632282461_1796722554"]={{"g8f6",1,"P",""}},
["1757277365_1884283424"]={{"d2d3",1,"P",""}},
["401912385_3055976831"]={{"c7c6",1,"P",""}},
["1374334571_2162049912"]={{"g1f3",1,"P",""}},
["3341784484_2264588873"]={{"d7d5",1,"P",""}},
["3793231902_627700083"]={{"c4b3",1,"P",""}},
["4273297221_3756421131"]={{"f8d6",1,"P",""}},
["2539980411_3269838958"]={{"b1c3",1,"P",""}},
["1129085005_1156739983"]={{"e8g8",1,"P",""}},
["4076996796_4038059894"]={{"e1g1",1,"P",""}},
["2994619542_662406624"]={{"b8c6",1,"A,Morphy",""}},
["4247475671_1705917951"]={{"d4e3",1,"A,Morphy",""}},
["320795015_1759548688"]={{"g8f6",1,"A,Morphy",""}},
["3880152175_1941485642"]={{"b1c3",1,"A,Morphy",""}},
["862917209_4121887659"]={{"f8b4",1,"A,Morphy",""}},
["3883868024_2526264112"]={{"c1d2",1,"A,Morphy",""}},
["2399195524_859011228"]={{"e8g8",1,"A,Morphy",""}},
["1062117749_2272193637"]={{"e1c1",1,"A,Morphy",""}},
["2198106138_2917262777"]={{"d7d5",1,"N",""}},
["2788410784_242415235"]={{"d1a4",1,"N",""}},
["1351362020_1378431100"]={{"f7f6",1,"N",""}},
["233146950_688887312"]={{"d2d4",1,"N",""}},
["272443279_761209033"]={{"c8d7",1,"N",""}},
["1183571758_2427335353"]={{"g1f3",12,"A,N,Tal,Fischer,Kasparov,Karpov",""},{"c2c3",1,"P,Karpov",""},{"d2d4",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"},{"b1c3",2,"A,D,Petrosian",""}},
["3494831329_2525664136"]={{"d7d6",6,"A,N,Tal,Fischer,Kasparov,Karpov",""},{"b8c6",4,"A,N,Fischer,Kasparov,Karpov",""},{"e7e6",2,"N,Karpov",""}},
["1069116878_1377058062"]={{"d2d4",5,"A,N,Tal,Fischer,Kasparov,Karpov",""},{"f1b5",1,"N",""}},
["576831495_1447332823"]={{"c5d4",5,"A,N,Tal,Fischer,Kasparov,Karpov",""}},
["1037431278_4276515674"]={{"f3d4",5,"A,N,Tal,Fischer,Kasparov,Karpov",""}},
["3573587226_315914027"]={{"g8f6",5,"A,N,Tal,Fischer,Kasparov,Karpov",""}},
["559415538_160193137"]={{"b1c3",5,"A,N,Tal,Fischer,Kasparov,Karpov",""}},
["4117855940_2409357712"]={{"a7a6",3,"A,N,Fischer,Kasparov",""},{"g7g6",1,"A,Tal",""},{"e7e6",1,"N,Karpov",""}},
["2796262303_1339762579"]={{"c1e3",1,"A,Fischer,Kasparov",""},{"c1g5",1,"A,Fischer,Kasparov",""},{"f1e2",1,"N",""}},
["1100177793_2580135248"]={{"e7e5",1,"A,Fischer,Kasparov",""}},
["2829598037_1331400788"]={{"d4b3",1,"A,Fischer,Kasparov",""}},
["2314530015_2576341992"]={{"c8e6",1,"A,Fischer,Kasparov",""}},
["2555780374_627764588"]={{"f2f3",1,"A,Fischer,Kasparov",""}},
["503612476_1592470749"]={{"f8e7",1,"A,Fischer,Kasparov",""}},
["2010576684_2404865301"]={{"d1d2",1,"A,Fischer,Kasparov",""}},
["2675115186_54678336"]={{"e8g8",1,"A,Fischer,Kasparov",""}},
["792556611_3072313273"]={{"e1c1",1,"A,Fischer,Kasparov",""}},
["3789190978_1233025979"]={{"e7e6",1,"A,Fischer,Kasparov",""}},
["3474047575_472934074"]={{"f2f4",1,"A,Fischer,Kasparov",""}},
["3663598249_426568492"]={{"f8e7",1,"A,Fischer,Kasparov",""}},
["3012321721_3369112292"]={{"d1f3",1,"A,Fischer,Kasparov",""}},
["4049834942_3784725684"]={{"d8c7",1,"A,Fischer,Kasparov",""}},
["3482069762_392528116"]={{"e1c1",1,"A,Fischer,Kasparov",""}},
["145545145_3643567124"]={{"b8d7",1,"A,Fischer,Kasparov",""}},
["1876490418_1763613301"]={{"e7e5",1,"N",""}},
["2263065702_3213670257"]={{"d4b3",1,"N",""}},
["2814342636_1767439565"]={{"f8e7",1,"N",""}},
["3463251708_3101984005"]={{"e1g1",1,"N",""}},
["700613239_1208453265"]={{"e8g8",1,"N",""}},
["3671122500_362291208"]={{"c1e3",1,"N",""}},
["1038618714_3280648907"]={{"c8e6",1,"N",""}},
["2981964649_2396004641"]={{"c1e3",1,"A,Tal",""}},
["1451612535_1489157090"]={{"f8g7",1,"A,Tal",""}},
["2929767860_3134938719"]={{"f2f3",1,"A,Tal",""}},
["686959774_3243941870"]={{"e8g8",1,"A,Tal",""}},
["2562481263_1963395863"]={{"d1d2",1,"A,Tal",""}},
["1880731633_4178709826"]={{"b8c6",1,"A,Tal",""}},
["1061994160_3150427485"]={{"f1c4",1,"A,Tal",""}},
["1650065155_3935275583"]={{"c8d7",1,"A,Tal",""}},
["53293052_2089643573"]={{"e1c1",1,"A,Tal",""}},
["2669409696_3563006871"]={{"d2d4",3,"A,N,Kasparov,Karpov",""},{"f1b5",1,"N,Fischer",""}},
["2193840233_3490684238"]={{"c5d4",3,"A,N,Kasparov,Karpov",""}},
["2641848704_2024629699"]={{"f3d4",3,"A,N,Kasparov,Karpov",""}},
["1973552500_2493473202"]={{"g7g6",1,"N",""},{"g8f6",2,"A,N,Kasparov,Karpov",""}},
["829313241_2513740035"]={{"c2c4",1,"N",""}},
["956609982_1507290759"]={{"f8g7",1,"N",""}},
["3240221053_3150875450"]={{"c1e3",1,"N",""}},
["639183715_1843139065"]={{"g8f6",1,"N",""}},
["3527521931_1988377763"]={{"b1c3",1,"N",""}},
["107530429_4036200258"]={{"e8g8",1,"N",""}},
["3055990860_1154356155"]={{"f1e2",1,"N",""}},
["2136331105_1644932701"]={{"d7d6",1,"N",""}},
["2426559054_2794782939"]={{"e1g1",1,"N",""}},
["877776391_3216257327"]={{"c8d7",1,"N",""}},
["3686452177_3671456913"]={{"f1e2",1,"N,Karpov",""}},
["315203836_4228923767"]={{"f8e7",1,"N,Karpov",""}},
["2065421292_766261439"]={{"e1g1",1,"N,Karpov",""}},
["2629064551_3712955691"]={{"e8g8",1,"N,Karpov",""}},
["1873164116_2161155506"]={{"f2f4",1,"N,Karpov",""}},
["2062149546_2240548900"]={{"b8c6",1,"N,Karpov",""}},
["901576427_3344541755"]={{"c1e3",1,"N,Karpov",""}},
["3531867381_290140920"]={{"c8d7",1,"N,Karpov",""}},
["2180683932_2412203240"]={{"b1c3",2,"A,N,Kasparov,Karpov",""}},
["1439950506_164689673"]={{"e7e5",1,"A,Kasparov",""},{"d7d6",1,"N,Karpov",""}},
["3169368702_3745700365"]={{"d4b5",1,"A,Kasparov",""}},
["2039338638_2832372512"]={{"d7d6",1,"A,Kasparov",""}},
["2524602273_1816935846"]={{"c1g5",1,"A,Kasparov",""}},
["3507207036_1793679758"]={{"a7a6",1,"A,Kasparov",""}},
["2194757159_2863245197"]={{"b5a3",1,"A,Kasparov",""}},
["3046829892_3862000861"]={{"b7b5",1,"A,Kasparov",""}},
["2236580305_3687249419"]={{"g5f6",1,"A,Kasparov",""}},
["1700689324_3600788345"]={{"g7f6",1,"A,Kasparov",""}},
["871502089_1269970400"]={{"c3d5",1,"A,Kasparov",""}},
["3041000884_3557826863"]={{"f6f5",1,"A,Kasparov",""}},
["4270150132_3284438665"]={{"d2d4",2,"N,Karpov",""}},
["3814587453_3348379728"]={{"c5d4",2,"N,Karpov",""}},
["4243181012_1865859293"]={{"f3d4",2,"N,Karpov",""}},
["339517728_2198127788"]={{"b8c6",1,"N",""},{"a7a6",1,"N,Karpov",""}},
["1533653089_3251731635"]={{"b1c3",1,"N",""}},
["2403389015_1204209490"]={{"d8c7",1,"N",""}},
["2981066475_2973045522"]={{"c1e3",1,"N",""}},
["1452770549_1730644433"]={{"a7a6",1,"N",""}},
["88959406_2808565714"]={{"f1e2",1,"N",""}},
["3426615939_2174939700"]={{"g8f6",1,"N",""}},
["946249579_2600132462"]={{"e1g1",1,"N",""}},
["3754499040_1780077306"]={{"f8e7",1,"N",""}},
["1206275195_1128530607"]={{"f1d3",1,"N,Karpov",""}},
["2567495910_664285164"]={{"g8f6",1,"N,Karpov",""}},
["1833991438_1019216566"]={{"e1g1",1,"N,Karpov",""}},
["2332031365_3424849698"]={{"d8c7",1,"N,Karpov",""}},
["3020964153_986766178"]={{"d1e2",1,"N,Karpov",""}},
["4069201443_2577989252"]={{"f8d6",1,"N,Karpov",""}},
["3122950021_3444464015"]={{"c1g5",1,"N,Karpov",""}},
["4250241880_3421177255"]={{"e7e6",1,"N,Karpov",""}},
["3550363213_2661619878"]={{"d1d2",1,"N,Karpov",""}},
["993775059_313532147"]={{"a7a6",1,"N,Karpov",""}},
["1759584392_3538999536"]={{"e1c1",1,"N,Karpov",""}},
["2948717619_481899536"]={{"c8d7",1,"N,Karpov",""}},
["3467971788_2327564314"]={{"f2f4",1,"N,Karpov",""}},
["3690650674_2414304652"]={{"f8e7",1,"N,Karpov",""}},
["3723474260_1138834998"]={{"g8f6",1,"P,Karpov",""}},
["699869372_1488524140"]={{"e4e5",1,"P,Karpov",""}},
["705133469_1810079175"]={{"f6d5",1,"P,Karpov",""}},
["3450278551_3511240909"]={{"d2d4",1,"P,Karpov",""}},
["3498032990_3575250452"]={{"c5d4",1,"P,Karpov",""}},
["3486224055_2109408921"]={{"g1f3",1,"P,Karpov",""}},
["1494136184_2074060712"]={{"b8c6",1,"P,Karpov",""}},
["375104569_961159095"]={{"c3d4",1,"P,Karpov",""}},
["2734241656_114875155"]={{"d7d6",1,"P,Karpov",""}},
["1292811863_3259397525"]={{"f1c4",1,"P,Karpov",""}},
["270270436_2467187447"]={{"d5b6",1,"P,Karpov",""}},
["4036197894_1965933647"]={{"c4b3",1,"P,Karpov",""}},
["3963488605_2409776439"]={{"d6e5",1,"P,Karpov",""}},
["438448434_3700406576"]={{"f3e5",1,"P,Karpov",""}},
["3006039220_1425586249"]={{"c6e5",1,"P,Karpov",""}},
["1979170348_3296565653"]={{"d4e5",1,"P,Karpov",""}},
["3060067276_1219671554"]={{"d8d1",1,"P,Karpov",""}},
["3297407814_3602657495"]={{"e1d1",1,"P,Karpov",""}},
["1532195559_2499708000"]={{"c5d4",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["1156006670_1012694253"]={{"c2c3",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["3749914996_4011028578"]={{"d4c3",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["298549229_3102408246"]={{"b1c3",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["1745963374_1722390512"]={{"b8c6",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["658790447_612118511"]={{"g1f3",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["2978046944_576229086"]={{"d7d6",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["1584851663_3871744088"]={{"f1c4",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["56863612_3079544634"]={{"e7e6",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["765992553_3804234299"]={{"e1g1",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["3389496034_304287663"]={{"g8f6",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["1046415114_159064821"]={{"d1e2",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["2026131472_2852325139"]={{"f8e7",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["286663424_2076147419"]={{"f1d1",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["3049162126_3303118377"]={{"e8g8",1,"A,G,Tal","Sicilian Defence: Smith-Morra Gambit"}},
["2460131608_381258072"]={{"b8c6",2,"A,D,Petrosian",""}},
["3723997273_1416376647"]={{"f2f4",1,"A",""},{"g2g3",1,"D,Petrosian",""}},
["3367526567_1362148561"]={{"g7g6",1,"A",""}},
["2356425994_1350270048"]={{"g1f3",1,"A",""}},
["447811269_1449123153"]={{"f8g7",1,"A",""}},
["3801375238_3024500972"]={{"f1c4",1,"A",""}},
["3212911541_3842901902"]={{"e7e6",1,"A",""}},
["2437584544_2956991119"]={{"f4f5",1,"A",""}},
["3027739608_1100806174"]={{"g6f5",1,"A",""}},
["858057322_1666602654"]={{"e4f5",1,"A",""}},
["2540095318_3188208272"]={{"g8e7",1,"A",""}},
["4277234279_2751567001"]={{"g7g6",1,"D,Petrosian",""}},
["3124576202_2773111848"]={{"f1g2",1,"D,Petrosian",""}},
["373240587_4221259684"]={{"f8g7",1,"D,Petrosian",""}},
["3994705864_427993625"]={{"d2d3",1,"D,Petrosian",""}},
["2438136124_3756771654"]={{"d7d6",1,"D,Petrosian",""}},
["2124711955_460679104"]={{"c1e3",1,"D,Petrosian",""}},
["2577168909_3446144259"]={{"e7e6",1,"D,Petrosian",""}},
["3075985176_2552881154"]={{"d1d2",1,"D,Petrosian",""}},
["1609710726_339535447"]={{"g8e7",1,"D,Petrosian",""}},
["704681465_793419110"]={{"g1e2",1,"D,Petrosian",""}},
["3923895959_1935601102"]={{"e8g8",1,"D,Petrosian",""}},
["1504679526_3338893623"]={{"e1g1",1,"D,Petrosian",""}},
["4008476121_1270530866"]={{"g7g6",1,"N,Fischer",""}},
["2854234228_1257309059"]={{"b5c6",1,"N,Fischer",""}},
["2094683841_4132427200"]={{"d7c6",1,"N,Fischer",""}},
["572682902_3797946734"]={{"d2d3",1,"N,Fischer",""}},
["1567304802_604598833"]={{"f8g7",1,"N,Fischer",""}},
["2773368993_3322976140"]={{"h2h3",1,"N,Fischer",""}},
["1830413984_1752434310"]={{"g8f6",1,"N,Fischer",""}},
["2571205448_1932274652"]={{"b1c3",1,"N,Fischer",""}},
["1298662782_4114321469"]={{"e8g8",1,"N,Fischer",""}},
["1313793463_3455178155"]={{"c8d7",1,"N",""}},
["792343880_1542664609"]={{"b5d7",1,"N",""}},
["1676363499_1844596080"]={{"d8d7",1,"N",""}},
["4051291445_3544064538"]={{"e1g1",1,"N",""}},
["383142334_601698190"]={{"b8c6",1,"N",""}},
["1501780223_1627953041"]={{"f1e1",1,"N",""}},
["527826371_3111418117"]={{"g8f6",1,"N",""}},
["3945619499_2720814175"]={{"c2c3",1,"N",""}},
["1883834961_1902336208"]={{"e7e6",1,"N",""}},
["1585626948_606946769"]={{"d2d4",1,"N",""}},
["1129976461_545125128"]={{"c5d4",1,"N",""}},
["1559110500_2296318853"]={{"c3d4",1,"N",""}},
["3897339941_3075329825"]={{"d6d5",1,"N",""}},
["100718895_3112419357"]={{"d2d4",5,"A,P,N,Fischer,Kasparov,Karpov",""}},
["467170534_3184752324"]={{"d7d5",5,"A,P,N,Fischer,Kasparov,Karpov",""}},
["1055899996_507536894"]={{"b1c3",2,"A,N,Fischer,Kasparov,Karpov",""},{"e4e5",1,"N",""},{"b1d2",1,"N,Karpov",""},{"e4d5",1,"P",""}},
["3938893674_2555895327"]={{"f8b4",1,"A,Fischer,Kasparov",""},{"g8f6",1,"N,Karpov",""}},
["1054257739_4218119812"]={{"e4e5",1,"A,Fischer,Kasparov",""}},
["1030152554_3358713903"]={{"c7c5",1,"A,Fischer,Kasparov",""}},
["1395020414_3025274762"]={{"a2a3",1,"A,Fischer,Kasparov",""}},
["627514062_32080881"]={{"b4c3",1,"A,Fischer,Kasparov",""}},
["1429548765_3979355114"]={{"b2c3",1,"A,Fischer,Kasparov",""}},
["975412766_1978607406"]={{"g8e7",1,"A,Fischer,Kasparov",""}},
["1339111265_1318673439"]={{"d1g4",1,"A,Fischer,Kasparov",""}},
["289373728_563817213"]={{"d8c7",1,"A,Fischer,Kasparov",""}},
["802211484_3613982397"]={{"g4g7",1,"A,Fischer,Kasparov",""}},
["2459649576_2979617767"]={{"h8g8",1,"A,Fischer,Kasparov",""}},
["503094944_1261694772"]={{"g7h7",1,"A,Fischer,Kasparov",""}},
["3672114653_2434979568"]={{"c5d4",1,"A,Fischer,Kasparov",""}},
["3310629940_964701821"]={{"g1e2",1,"A,Fischer,Kasparov",""}},
["112543578_1704222421"]={{"b8c6",1,"A,Fischer,Kasparov",""}},
["1239438875_658630346"]={{"f2f4",1,"A,Fischer,Kasparov",""}},
["1555007205_572353372"]={{"c8d7",1,"A,Fischer,Kasparov",""}},
["513680002_2198860613"]={{"c1g5",1,"N,Karpov",""}},
["1508886111_2242555757"]={{"f8e7",1,"N,Karpov",""}},
["809350479_1410782885"]={{"e4e5",1,"N,Karpov",""}},
["864937582_1733056526"]={{"f6d7",1,"N,Karpov",""}},
["1905183658_3078628663"]={{"g5e7",1,"N,Karpov",""}},
["1582725445_3198987962"]={{"d8e7",1,"N,Karpov",""}},
["4167153419_513194283"]={{"f2f4",1,"N,Karpov",""}},
["3979241461_466236605"]={{"e8g8",1,"N,Karpov",""}},
["1566578436_2945949764"]={{"g1f3",1,"N,Karpov",""}},
["3416599755_2847080821"]={{"c7c5",1,"N,Karpov",""}},
["2783289311_3587239632"]={{"d1d2",1,"N,Karpov",""}},
["1296067649_1506142341"]={{"b8c6",1,"N,Karpov",""}},
["34962688_454054042"]={{"e1c1",1,"N,Karpov",""}},
["1029673597_756738901"]={{"c7c5",1,"N",""}},
["1394549097_1366885616"]={{"c2c3",1,"N",""}},
["3363523347_2184579199"]={{"b8c6",1,"N",""}},
["2267961938_3236147296"]={{"g1f3",1,"N",""}},
["300638621_3334934865"]={{"d8b6",1,"N",""}},
["1850243705_1105868218"]={{"a2a3",1,"N",""}},
["403256009_4098994625"]={{"c5c4",1,"N",""}},
["426643220_3373304082"]={{"b2b4",1,"N",""}},
["3645436577_613061839"]={{"c4b3",1,"N",""}},
["1175355931_1610124957"]={{"c1b2",1,"N",""}},
["3855865744_2064816128"]={{"g8f6",1,"N,Karpov",""}},
["294341240_1615508826"]={{"e4e5",1,"N,Karpov",""}},
["305863001_1393572849"]={{"f6d7",1,"N,Karpov",""}},
["1345860765_2212251336"]={{"f1d3",1,"N,Karpov",""}},
["2396428288_3875564427"]={{"c7c5",1,"N,Karpov",""}},
["3767937812_2606990382"]={{"c2c3",1,"N,Karpov",""}},
["2079474030_1210878113"]={{"b8c6",1,"N,Karpov",""}},
["883380271_184103102"]={{"g1e2",1,"N,Karpov",""}},
["4148568897_1458389014"]={{"c5d4",1,"N,Karpov",""}},
["3908178600_4266637467"]={{"c3d4",1,"N,Karpov",""}},
["1548780009_3252517951"]={{"f7f6",1,"N,Karpov",""}},
["20524619_3137067603"]={{"e5f6",1,"N,Karpov",""}},
["1124731779_1295465854"]={{"d7f6",1,"N,Karpov",""}},
["1017833421_1782418276"]={{"d2f3",1,"N,Karpov",""}},
["2402235114_1195019315"]={{"f8d6",1,"N,Karpov",""}},
["602720591_3798725005"]={{"e6d5",1,"P",""}},
["4125416197_3188573351"]={{"g1f3",1,"P",""}},
["1663164618_3089720726"]={{"g8f6",1,"P",""}},
["2541321506_2742110412"]={{"f1d3",1,"P",""}},
["1234686399_3350029711"]={{"f8d6",1,"P",""}},
["541556865_3668893162"]={{"e1g1",1,"P",""}},
["3353871370_709742718"]={{"e8g8",1,"P",""}},
["888824889_2010282215"]={{"c1g5",1,"P",""}},
["1938522340_1903633615"]={{"c8g4",1,"P",""}},
["4051618851_934130590"]={{"b1d2",1,"P",""}},
["709024495_1392463456"]={{"b8d7",1,"P",""}},
["1859481616_3660914459"]={{"d2d4",14,"A,D,P,N,G,Tal,Petrosian,Karpov,Alien",""},{"g1f3",1,"N",""}},
["1930288601_3731204546"]={{"d7d5",14,"A,D,P,N,G,Tal,Petrosian,Karpov,Alien",""}},
["1446668387_2113321720"]={{"b1c3",8,"A,D,G,Tal,Petrosian,Karpov,Alien",""},{"e4e5",2,"A,N",""},{"e4d5",2,"A,P",""},{"f2f3",1,"A",""},{"b1d2",1,"A,G,Tal,Alien",""}},
["2182288981_4225827097"]={{"d5e4",8,"A,D,G,Tal,Petrosian,Karpov,Alien",""}},
["2509064341_2942381466"]={{"c3e4",8,"A,D,G,Tal,Petrosian,Karpov,Alien",""}},
["928399271_3841349942"]={{"c8f5",4,"A,D,G,Tal,Petrosian,Karpov,Alien","Caro-Kann: Martian Gambit"},{"b8d7",1,"D,Karpov",""},{"g8f6",4,"A,G,Tal,Alien","Caro-Kann: Alien Gambit"}},
["122113109_931069267"]={{"e4g3",1,"D,Petrosian,Karpov",""},{"e4g5",3,"A,G,Tal,Alien","Caro-Kann: Martian Gambit"}},
["896623973_577042667"]={{"f5g6",1,"D,Petrosian,Karpov",""}},
["1230444601_3764244273"]={{"h2h4",1,"D,Petrosian,Karpov",""}},
["992889991_2774822616"]={{"h7h6",1,"D,Petrosian,Karpov",""}},
["2139161708_3197753002"]={{"g1f3",1,"D,Petrosian,Karpov",""}},
["3913564067_3099424667"]={{"b8d7",1,"D,Petrosian,Karpov",""}},
["1240410692_945323767"]={{"h4h5",1,"D,Petrosian,Karpov",""}},
["1034014282_2306409406"]={{"g6h7",1,"D,Petrosian,Karpov",""}},
["1085654949_4032981797"]={{"f1d3",1,"D,Petrosian,Karpov",""}},
["2656791352_2495497830"]={{"h7d3",1,"D,Petrosian,Karpov",""}},
["305035850_1905118169"]={{"d1d3",1,"D,Petrosian,Karpov",""}},
["2033621088_3982713565"]={{"e7e6",1,"D,Petrosian,Karpov",""}},
["1476210037_3089989596"]={{"c1f4",1,"D,Petrosian,Karpov",""}},
["2663769224_1758085602"]={{"d8a5",1,"D,Petrosian,Karpov",""}},
["1033480285_450072212"]={{"e1e2",1,"D,Petrosian,Karpov",""}},
["2398760837_2857871872"]={{"g8f6",1,"D,Petrosian,Karpov",""}},
["2549951040_1678987354"]={{"e4g5",1,"D,Karpov",""}},
["1653262914_1133536195"]={{"g8f6",1,"D,Karpov",""}},
["2530367402_1489522329"]={{"f1d3",1,"D,Karpov",""}},
["1211956023_1007969242"]={{"e7e6",1,"D,Karpov",""}},
["1727483426_1767538395"]={{"g1f3",1,"D,Karpov",""}},
["4029838829_1870585834"]={{"f8d6",1,"D,Karpov",""}},
["2581734611_1920821135"]={{"d1e2",1,"D,Karpov",""}},
["3749278665_3506782825"]={{"h7h6",1,"D,Karpov",""}},
["2614508322_3405314587"]={{"g5e4",1,"D,Karpov",""}},
["1856101152_3984312706"]={{"f6e4",1,"D,Karpov",""}},
["2015817484_488669199"]={{"e2e4",1,"D,Karpov",""}},
["1984219235_106112807"]={{"d8c7",1,"D,Karpov",""}},
["1435122498_1319908435"]={{"c8f5",2,"A,N",""}},
["1704675504_2636419126"]={{"g1f3",1,"N",""},{"b1c3",1,"A",""}},
["4083053439_2600481031"]={{"e7e6",1,"N",""}},
["3717580394_3461229574"]={{"f1e2",1,"N",""}},
["350661959_3901460960"]={{"c6c5",1,"N",""}},
["2692399348_4108559366"]={{"e1g1",1,"N",""}},
["1205159039_67152274"]={{"b8c6",1,"N",""}},
["142628158_1188368781"]={{"c2c3",1,"N",""}},
["2481209156_2509905154"]={{"g8e7",1,"N",""}},
["2981246598_456338391"]={{"e7e6",1,"A",""}},
["2675540883_1316828886"]={{"g2g4",1,"A",""}},
["2149478214_4079468061"]={{"f5g6",1,"A",""}},
["4231533082_824084935"]={{"g1e2",1,"A",""}},
["1071210868_1829435759"]={{"g8e7",1,"A",""}},
["1244383243_1451000414"]={{"h2h4",1,"A",""}},
["944938165_323298231"]={{"h7h6",1,"A",""}},
["1262051440_2178756235"]={{"c6d5",2,"A,P",""}},
["1704989525_2660931248"]={{"c2c4",1,"A",""},{"f1d3",1,"P",""}},
["1842017842_1385781556"]={{"g8f6",1,"A",""}},
["2576509914_1237415022"]={{"b1c3",1,"A",""}},
["1304106476_3486961551"]={{"e7e6",1,"A",""}},
["1668325625_2593706638"]={{"g1f3",1,"A",""}},
["4122319670_2629596095"]={{"f8b4",1,"A",""}},
["564499991_4286630692"]={{"c4d5",1,"A",""}},
["528115641_572563871"]={{"f6d5",1,"A",""}},
["3976876427_1079451862"]={{"f1d3",1,"A",""}},
["870645014_613092757"]={{"b8c6",1,"A",""}},
["2092035159_1717482890"]={{"e1g1",1,"A",""}},
["2602461404_2529015838"]={{"e8g8",1,"A",""}},
["4161817567_3692150314"]={{"d7d5",1,"N",""}},
["3710385765_2139270416"]={{"b1c3",1,"N",""}},
["151945299_4187297521"]={{"c8g4",1,"N",""}},
["2348534932_3209658784"]={{"h2h3",1,"N",""}},
["1135372949_288034986"]={{"g4f3",1,"N",""}},
["3346634692_1168952708"]={{"d1f3",1,"N",""}},
["751841937_2059599312"]={{"e7e6",1,"N",""}},
["35358596_797761745"]={{"d2d4",1,"N",""}},
["532884045_735860232"]={{"g8f6",1,"N",""}},
["3952850853_813988690"]={{"f1d3",1,"N",""}},
["896867128_1415075345"]={{"f8e7",1,"N",""}},
["3496538441_108493641"]={{"d5e4",1,"A",""}},
["3354832777_1391941578"]={{"f3e4",1,"A",""}},
["871595122_3554630604"]={{"e7e5",1,"A",""}},
["3670548646_88962760"]={{"g1f3",1,"A",""}},
["1275927401_57268217"]={{"e5d4",1,"A",""}},
["1149635856_565034946"]={{"f1c4",1,"A",""}},
["429083811_1894088864"]={{"g8f6",1,"A",""}},
["3989557579_1807592954"]={{"d1d4",1,"A",""}},
["2333482627_1343031008"]={{"d8e7",1,"A",""}},
["3142500296_4198939635"]={{"b8c6",1,"P",""}},
["4095454857_3096642540"]={{"c2c3",1,"P",""}},
["1870644467_1809583971"]={{"g8f6",1,"P",""}},
["2603047195_1887707705"]={{"c1f4",1,"P",""}},
["1377800422_2690849799"]={{"c8g4",1,"P",""}},
["3505052705_3870919510"]={{"d1b3",1,"P",""}},
["19672284_306855527"]={{"d8d7",1,"P",""}},
["3272516175_4289623148"]={{"e4g5",4,"A,G,Tal,Alien","Caro-Kann: Alien Gambit"}},
["913916493_3626846197"]={{"h7h6",3,"A,G,Tal,Alien","Caro-Kann: Alien Gambit declined with ...e6"},{"e7e6",1,"A,G,Alien","Caro-Kann: Alien Gambit declined with ...e6"}},
["1926630054_3285254023"]={{"g5f7",3,"A,G,Tal,Alien","Caro-Kann: Alien Gambit, Nxf7 sacrifice"}},
["2469040346_3876042754"]={{"e8f7",3,"A,G,Tal,Alien","Caro-Kann: Alien Gambit, Nxf7 sacrifice"}},
["3199902970_2929175784"]={{"d1f3",3,"A,G,Tal,Alien","Caro-Kann: Alien Gambit, Nxf7 sacrifice"}},
["4233451261_2278648504"]={{"f7g6",2,"A,G,Tal,Alien","Caro-Kann: Alien Gambit, Nxf7 sacrifice"},{"f7g8",1,"A,G,Alien","Caro-Kann: Alien Gambit, Nxf7 sacrifice"}},
["3146004789_2834459620"]={{"f1d3",2,"A,G,Tal,Alien","Caro-Kann: Alien Gambit, Nxf7 sacrifice"}},
["2366013103_413419270"]={{"d5e4",1,"A,G,Tal,Alien",""}},
["2593661039_1277455237"]={{"d2e4",1,"A,G,Tal,Alien",""}},
["1765356283_2745752648"]={{"f1c4",1,"A,G,Alien","Caro-Kann: Alien Gambit, 7...Kg8"}},
["875328328_4074824490"]={{"e7e6",1,"A,G,Alien","Caro-Kann: Alien Gambit, 7...Kg8"}},
["451397213_2813263403"]={{"c1f4",1,"A,G,Alien","Caro-Kann: Alien Gambit, 7...Kg8"}},
["414381912_2372098804"]={{"f1d3",1,"A,G,Alien","Caro-Kann: Alien Gambit declined with ...e6"}},
["3327941573_3921639351"]={{"h7h6",1,"A,G,Alien","Caro-Kann: Alien Gambit declined with ...e6"}},
["2196968238_4064464837"]={{"g5f3",1,"A,G,Alien","Caro-Kann: Alien Gambit declined with ...e6"}},
["1988243496_543302923"]={{"c6c5",1,"A,G,Alien","Caro-Kann: Alien Gambit declined with ...e6"}},
["4063276119_285069002"]={{"f5g6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit declined with ...e6"},{"h7h6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit declined with ...e6"},{"e7e6",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["2383859979_3536124176"]={{"g1f3",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Ne6 sacrifice"}},
["416541380_3571472417"]={{"h7h6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Ne6 sacrifice"}},
["1551671855_3474841683"]={{"g5e6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Ne6 sacrifice"}},
["937510885_4238402827"]={{"f7e6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Ne6 sacrifice"}},
["1694529097_317003277"]={{"f3e5",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Ne6 sacrifice"}},
["3063932092_184579768"]={{"g5f7",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["1466138304_802631997"]={{"e8f7",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["2062764768_1715938775"]={{"d1h5",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3322320010_2255226593"]={{"f5g6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3122719190_1146433851"]={{"f1c4",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3879053413_354225753"]={{"e7e6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3388874096_1079186264"]={{"c4e6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["387477184_1120671648"]={{"f7e6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["4113325363_2949270710"]={{"h5g6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["431187184_3498480294"]={{"g8f6",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3991664920_3420372988"]={{"g1f3",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["2066662103_3455721165"]={{"d8a5",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3631386114_3219378619"]={{"c1d2",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["2953658622_440603159"]={{"a5b5",1,"A,G,Tal,Alien","Caro-Kann: Martian Gambit, Qh5+ trap"}},
["3707443522_1169413067"]={{"g5f3",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["680147524_2543008005"]={{"f5g6",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["1420576536_1437208287"]={{"f1d3",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["2319641477_829825948"]={{"g6d3",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["3890295189_4222476028"]={{"d1d3",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["2365182911_1732474872"]={{"b8d7",1,"A,G,Alien","Caro-Kann: Martian Gambit declined with ...e6"}},
["234674560_1331613222"]={{"e4d5",2,"A,N",""}},
["285200787_3010812501"]={{"d8d5",1,"A",""},{"g8f6",1,"N",""}},
["4052570883_642695253"]={{"b1c3",1,"A",""}},
["631516469_2690218932"]={{"d5a5",1,"A",""}},
["4002971333_3377816261"]={{"d2d4",1,"A",""}},
["4081111820_3439711260"]={{"g8f6",1,"A",""}},
["119033572_3596482886"]={{"g1f3",1,"A",""}},
["2447209771_3497613431"]={{"c7c6",1,"A",""}},
["3619907841_3867253360"]={{"f1c4",1,"A",""}},
["2329290930_3083445522"]={{"c8f5",1,"A",""}},
["3133627200_1681981815"]={{"c4d3",1,"A",""}},
["2784916707_119933714"]={{"f5d3",1,"A",""}},
["683217186_1496832492"]={{"d1d3",1,"A",""}},
["1134686984_3319361768"]={{"e7e6",1,"A",""}},
["3836169339_2821551887"]={{"d2d4",1,"N",""}},
["4185907634_2893922774"]={{"f6d5",1,"N",""}},
["185587584_3456778399"]={{"g1f3",1,"N",""}},
["2647321679_3358515630"]={{"g7g6",1,"N",""}},
["3641096674_3378848031"]={{"f1e2",1,"N",""}},
["276157135_4020280569"]={{"f8g7",1,"N",""}},
["3897605644_230259012"]={{"e1g1",1,"N",""}},
["268384903_4250563792"]={{"e8g8",1,"N",""}},
["4243413684_2697321545"]={{"c2c4",1,"N",""}},
["4102537171_1824920525"]={{"d5b6",1,"N",""}},
["3342656789_676557722"]={{"d2d4",3,"A,D,Petrosian,Kasparov",""}},
["3672393948_738444611"]={{"g8f6",3,"A,D,Petrosian,Kasparov",""}},
["784127284_928770073"]={{"b1c3",3,"A,D,Petrosian,Kasparov",""}},
["4204112642_2974569464"]={{"g7g6",3,"A,D,Petrosian,Kasparov",""}},
["3193568943_2953286473"]={{"f2f4",1,"A",""},{"g1f3",1,"D,Petrosian",""},{"c1e3",1,"A,Kasparov",""}},
["2870357585_3042647775"]={{"f8g7",1,"A",""}},
["1395868306_1464007522"]={{"g1f3",1,"A",""}},
["3321264477_1365662291"]={{"e8g8",1,"A",""}},
["1974995372_3845901994"]={{"f1d3",1,"A",""}},
["2874582321_2179458025"]={{"b8c6",1,"A",""}},
["3825448048_3274857462"]={{"e1g1",1,"A",""}},
["681362784_3055759992"]={{"f8g7",1,"D,Petrosian",""}},
["3501828515_1413142469"]={{"f1e2",2,"D,N,Petrosian",""}},
["432718478_1929341475"]={{"e8g8",2,"D,N,Petrosian",""}},
["2844045951_3332570842"]={{"e1g1",2,"D,N,Petrosian",""}},
["225912374_3749957422"]={{"c7c6",2,"D,N,Petrosian",""}},
["1265187356_3917155625"]={{"a2a4",2,"D,N,Petrosian",""}},
["920245209_2566669448"]={{"b8d7",2,"D,N,Petrosian",""}},
["1499532465_1712654730"]={{"f8g7",1,"A,Kasparov",""}},
["2705612914_2215439415"]={{"d1d2",1,"A,Kasparov",""}},
["1239520236_135916130"]={{"c7c6",1,"A,Kasparov",""}},
["268406726_1054943333"]={{"f2f3",1,"A,Kasparov",""}},
["2309822188_1163979220"]={{"b7b5",1,"A,Kasparov",""}},
["3111680121_2023189250"]={{"g2g4",1,"A,Kasparov",""}},
["2787087532_3318604745"]={{"b8d7",1,"A,Kasparov",""}},
["1812412823_3984989613"]={{"d2d4",1,"N",""}},
["1910477918_3923159924"]={{"f8g7",1,"N",""}},
["2314926237_198135497"]={{"b1c3",1,"N",""}},
["1574143659_2379805992"]={{"d7d6",1,"N",""}},
["2988707716_1229347758"]={{"g1f3",1,"N",""}},
["618738763_1331886751"]={{"g8f6",1,"N",""}},
["3700683218_4153798726"]={{"e4e5",1,"A",""}},
["3743654643_3301932781"]={{"f6d5",1,"A",""}},
["948161529_2120592359"]={{"d2d4",1,"A",""}},
["626746928_2050301246"]={{"d7d6",1,"A",""}},
["3400331039_3198923704"]={{"g1f3",1,"A",""}},
["1550439632_3096384137"]={{"c8g4",1,"A",""}},
["3734804503_4267017688"]={{"f1e2",1,"A",""}},
["401601338_3633330238"]={{"e7e6",1,"A",""}},
["958678575_2380145983"]={{"e1g1",1,"A",""}},
["3733701284_2101160107"]={{"f8e7",1,"A",""}},
["3076108724_2894156131"]={{"c2c4",1,"A",""}},
["3207812307_1619173095"]={{"d5b6",1,"A",""}},
["1738440059_2920834307"]={{"d2d4",1,"N",""}},
["2051461298_2856899546"]={{"d7d5",1,"N",""}},
["1601266952_165396704"]={{"e4e5",1,"N",""}},
["1556166185_981552715"]={{"c8f5",1,"N",""}},
["1825588699_3909741102"]={{"g1f3",1,"N",""}},
["4195712532_4012722975"]={{"e7e6",1,"N",""}},
["3571370753_3127072286"]={{"f1e2",1,"N",""}},
["497917996_2628185080"]={{"f8e7",1,"N",""}},
["1621277435_3360022949"]={{"d7d5",10,"A,D,P,N,Petrosian,Fischer,Kasparov,Karpov,Carlsen,Capablanca",""},{"g8f6",19,"A,D,P,N,G,Tal,Fischer,Kasparov,Karpov,Carlsen,Morphy",""},{"f7f5",2,"A,D,Fischer",""}},
["1167396673_1809248927"]={{"c2c4",7,"A,D,P,N,Petrosian,Fischer,Kasparov,Karpov,Capablanca",""},{"c1f4",1,"P,Carlsen",""},{"g1f3",1,"P,Capablanca",""},{"b1c3",1,"A",""}},
["1308617254_2815769883"]={{"e7e6",3,"A,P,N,Fischer,Karpov,Capablanca",""},{"d5c4",1,"N",""},{"c7c6",3,"A,D,N,Petrosian,Kasparov",""}},
["1664376627_4070252570"]={{"b1c3",3,"A,P,N,Fischer,Karpov,Capablanca",""}},
["3072139525_1955372027"]={{"g8f6",2,"P,N,Fischer,Karpov,Capablanca",""},{"c7c5",1,"A",""}},
["1128643821_1876211361"]={{"c1g5",1,"N,Fischer,Capablanca",""},{"c4d5",1,"P,Karpov,Capablanca",""}},
["70539312_1769073289"]={{"f8e7",1,"N,Fischer,Capablanca",""}},
["1843800864_3100480321"]={{"e2e3",1,"N,Fischer,Capablanca",""}},
["3522363818_2298818665"]={{"e8g8",1,"N,Fischer,Capablanca",""}},
["1639805275_1029219472"]={{"g1f3",1,"N,Fischer,Capablanca",""}},
["4151855764_997983649"]={{"h7h6",1,"N,Fischer,Capablanca",""}},
["3017212543_545373651"]={{"g5h4",1,"N,Fischer,Capablanca",""}},
["2503832223_1455385128"]={{"b7b6",1,"N,Fischer,Capablanca",""}},
["1273882536_336271524"]={{"c4d5",1,"N,Fischer,Capablanca",""}},
["1966216710_3383456287"]={{"f6d5",1,"N,Fischer,Capablanca",""}},
["2269257780_2883384150"]={{"h4e7",1,"N,Fischer,Capablanca",""}},
["313663670_2185082724"]={{"d8e7",1,"N,Fischer,Capablanca",""}},
["3028676344_570925301"]={{"c3d5",1,"N,Fischer,Capablanca",""}},
["724582655_1188666472"]={{"e6d5",1,"N,Fischer,Capablanca",""}},
["2107264323_2994002970"]={{"e6d5",1,"P,Karpov,Capablanca",""}},
["2878496521_3994216752"]={{"c1g5",1,"P,Karpov,Capablanca",""}},
["3974347732_3904353560"]={{"f8e7",1,"P,Karpov,Capablanca",""}},
["2234632388_957074640"]={{"e2e3",1,"P,Karpov,Capablanca",""}},
["958718542_147025912"]={{"e8g8",1,"P,Karpov,Capablanca",""}},
["2305462975_3164535553"]={{"f1d3",1,"P,Karpov,Capablanca",""}},
["1468284450_3628258882"]={{"b8d7",1,"P,Karpov,Capablanca",""}},
["4147063749_1487396654"]={{"d1c2",1,"P,Karpov,Capablanca",""}},
["1145819791_4250901954"]={{"f8e8",1,"P,Karpov,Capablanca",""}},
["3646788113_149910622"]={{"c4d5",1,"A",""}},
["3884082111_3578732261"]={{"e6d5",1,"A",""}},
["831156725_2301176783"]={{"g1f3",1,"A",""}},
["2806991418_2400029438"]={{"b8c6",1,"A",""}},
["3894041467_3453498081"]={{"g2g3",1,"A",""}},
["3407642949_1035310911"]={{"g8f6",1,"A",""}},
["1061428397_653113957"]={{"f1g2",1,"A",""}},
["2470842476_2017239529"]={{"f8e7",1,"A",""}},
["4204028796_2843793441"]={{"e1g1",1,"A",""}},
["490465271_1499714997"]={{"e8g8",1,"A",""}},
["1192713741_906208422"]={{"g1f3",1,"N",""}},
["3520226754_807863703"]={{"g8f6",1,"N",""}},
["629864490_729753805"]={{"e2e3",1,"N",""}},
["2577388192_448236517"]={{"e7e6",1,"N",""}},
["3075762101_1341757156"]={{"f1c4",1,"N",""}},
["3416669371_2316963523"]={{"c7c5",1,"N",""}},
["2783350703_4135182694"]={{"e1g1",1,"N",""}},
["1112083236_110816498"]={{"a7a6",1,"N",""}},
["294905471_3336186609"]={{"d1e2",1,"N",""}},
["1460187493_1705119511"]={{"b7b5",1,"N",""}},
["1742594032_1482001857"]={{"c4b3",1,"N",""}},
["2070980779_2732199097"]={{"c8b7",1,"N",""}},
["1295364472_2554548821"]={{"f1d1",1,"N",""}},
["3919386614_656259751"]={{"b8d7",1,"N",""}},
["1228276241_2818094027"]={{"b1c3",1,"N",""}},
["2636086311_569313322"]={{"c5d4",1,"N",""}},
["199357964_2435710748"]={{"g1f3",3,"A,D,N,Petrosian,Kasparov",""}},
["2636434883_2533973549"]={{"g8f6",3,"A,D,N,Petrosian,Kasparov",""}},
["1769754667_2354148215"]={{"b1c3",3,"A,D,N,Petrosian,Kasparov",""}},
["3176476189_172411030"]={{"d5c4",1,"D,Petrosian",""},{"e7e6",2,"A,N,Kasparov",""}},
["3082656310_2609926443"]={{"a2a4",1,"D,Petrosian",""}},
["3389879283_3927382154"]={{"c8f5",1,"D,Petrosian",""}},
["4196139009_966769903"]={{"e2e3",1,"D,Petrosian",""}},
["1175005835_139927495"]={{"e7e6",1,"D,Petrosian",""}},
["1757585310_1561920198"]={{"f1c4",1,"D,Petrosian",""}},
["338740368_2566560481"]={{"f8b4",1,"D,Petrosian",""}},
["3223374257_4224066170"]={{"e1g1",1,"D,Petrosian",""}},
["663702842_186986478"]={{"e8g8",1,"D,Petrosian",""}},
["3567070473_1455064951"]={{"d1e2",1,"D,Petrosian",""}},
["2449898003_4123173521"]={{"b8d7",1,"D,Petrosian",""}},
["2476645128_1594414487"]={{"e2e3",1,"N,Kasparov",""},{"c1g5",1,"A,Kasparov",""}},
["797684098_1858107071"]={{"b8d7",1,"N,Kasparov",""}},
["2401281125_3995434963"]={{"f1d3",1,"N,Kasparov",""}},
["1372457208_2331595408"]={{"d5c4",1,"N,Kasparov",""}},
["1529265363_456117037"]={{"d3c4",1,"N,Kasparov",""}},
["1710787021_3974325773"]={{"b7b5",1,"N,Kasparov",""}},
["1429071704_3507807451"]={{"c4d3",1,"N,Kasparov",""}},
["1242876155_2993942206"]={{"a7a6",1,"N,Kasparov",""}},
["432940448_1915955389"]={{"e3e4",1,"N,Kasparov",""}},
["1822996143_902830513"]={{"c6c5",1,"N,Kasparov",""}},
["3572465621_1504545215"]={{"d5c4",1,"A,Kasparov",""}},
["3725052926_3363508226"]={{"e2e4",1,"A,Kasparov",""}},
["2344005878_3903036002"]={{"b7b5",1,"A,Kasparov",""}},
["3143884387_3579058356"]={{"e4e5",1,"A,Kasparov",""}},
["3100872002_3859715615"]={{"h7h6",1,"A,Kasparov",""}},
["4236035497_4260572781"]={{"g5h4",1,"A,Kasparov",""}},
["3667309897_2345531798"]={{"g7g5",1,"A,Kasparov",""}},
["3726609563_3725824253"]={{"f3g5",1,"A,Kasparov",""}},
["4005336713_4057767775"]={{"h6g5",1,"A,Kasparov",""}},
["69410211_2508096360"]={{"h4g5",1,"A,Kasparov",""}},
["3860550743_514830847"]={{"b8d7",1,"A,Kasparov",""}},
["2499421971_3541945599"]={{"c2c4",16,"A,D,P,N,G,Tal,Fischer,Kasparov,Karpov,Carlsen",""},{"c1f4",1,"P",""},{"c1g5",1,"A,Morphy",""},{"g1f3",1,"N",""}},
["2626732660_522060667"]={{"e7e6",6,"A,D,P,N,Fischer,Karpov,Carlsen",""},{"g7g6",6,"A,N,Fischer,Kasparov",""},{"c7c5",2,"A,G,Tal,Kasparov",""},{"d7d6",1,"N",""},{"e7e5",1,"A,G","Budapest Gambit"}},
["2992338785_1246764666"]={{"g2g3",1,"P,Karpov,Carlsen",""},{"b1c3",3,"A,N,Fischer,Karpov",""},{"g1f3",2,"D,P,Karpov,Carlsen",""}},
["2438835551_3124607908"]={{"d7d5",1,"P,Karpov,Carlsen",""}},
["3026852069_430876830"]={{"f1g2",1,"P,Karpov,Carlsen",""}},
["409474084_1199551250"]={{"f8e7",1,"P,Karpov,Carlsen",""}},
["1908041524_2529413850"]={{"g1f3",1,"P,Karpov,Carlsen",""}},
["3883883771_2431085547"]={{"e8g8",1,"P,Karpov,Carlsen",""}},
["1462840330_616234770"]={{"e1g1",1,"P,Karpov,Carlsen",""}},
["4089624643_1033621222"]={{"d5c4",1,"P,Karpov,Carlsen",""}},
["4180282472_2890749787"]={{"d1c2",1,"P,Karpov,Carlsen",""}},
["1246688546_162862519"]={{"a7a6",1,"P,Karpov,Carlsen",""}},
["429135993_3388330932"]={{"c2c4",1,"P,Karpov,Carlsen",""}},
["3843921247_2709360132"]={{"b7b5",1,"P,Karpov,Carlsen",""}},
["3586718666_2626292946"]={{"c4c2",1,"P,Karpov,Carlsen",""}},
["145124433_1621751335"]={{"c8b7",1,"P,Karpov,Carlsen",""}},
["1718749527_3427247515"]={{"f8b4",3,"A,N,Fischer,Karpov",""}},
["2992768118_2944081152"]={{"e2e3",1,"N,Fischer,Karpov",""},{"d1c2",1,"N,Karpov",""},{"a2a3",1,"A",""}},
["242691836_2662579752"]={{"e8g8",1,"N,Fischer,Karpov",""}},
["3191430669_720251601"]={{"f1d3",1,"N,Fischer,Karpov",""}},
["1624765072_1311901586"]={{"d7d5",1,"N,Fischer,Karpov",""}},
["1172326186_3986756776"]={{"g1f3",1,"N,Fischer,Karpov",""}},
["3542449381_3951408537"]={{"c7c5",1,"N,Fischer,Karpov",""}},
["3177566193_2548455996"]={{"e1g1",1,"N,Fischer,Karpov",""}},
["429284280_2395433928"]={{"b8c6",1,"N,Fischer,Karpov",""}},
["1455639289_3423785943"]={{"a2a3",1,"N,Fischer,Karpov",""}},
["545391177_2041141164"]={{"b4c3",1,"N,Fischer,Karpov",""}},
["1355822682_2507208631"]={{"b2c3",1,"N,Fischer,Karpov",""}},
["1069975193_229634931"]={{"d5c4",1,"N,Fischer,Karpov",""}},
["892220082_2625202894"]={{"d3c4",1,"N,Fischer,Karpov",""}},
["200279980_1807075310"]={{"d8c7",1,"N,Fischer,Karpov",""}},
["17235260_176381932"]={{"e8g8",1,"N,Karpov",""}},
["2974322125_3202272021"]={{"a2a3",1,"N,Karpov",""}},
["3339306365_191188846"]={{"b4c3",1,"N,Karpov",""}},
["3076256110_3887918965"]={{"c2c3",1,"N,Karpov",""}},
["2743642624_1876352484"]={{"b7b6",1,"N,Karpov",""}},
["2102935351_761442152"]={{"c1g5",1,"N,Karpov",""}},
["975821802_734524224"]={{"c8b7",1,"N,Karpov",""}},
["208454201_291417516"]={{"e2e3",1,"N,Karpov",""}},
["2960779443_546705028"]={{"d7d6",1,"N,Karpov",""}},
["1603166620_3825770498"]={{"f2f3",1,"N,Karpov",""}},
["3655137462_2676580787"]={{"b8d7",1,"N,Karpov",""}},
["3290647750_448829819"]={{"b4c3",1,"A",""}},
["3027335381_4128848224"]={{"b2c3",1,"A",""}},
["3681011734_1858485668"]={{"c7c5",1,"A",""}},
["3039263490_312857089"]={{"e2e3",1,"A",""}},
["154292616_594374953"]={{"b8c6",1,"A",""}},
["1181171913_1639500086"]={{"f1d3",1,"A",""}},
["2559175764_90498165"]={{"e8g8",1,"A",""}},
["684170405_2973331596"]={{"g1e2",1,"A",""}},
["3945197515_3979149348"]={{"b7b6",1,"A",""}},
["905345788_2946069160"]={{"e3e4",1,"A",""}},
["1083238899_3900326820"]={{"f6e8",1,"A",""}},
["614354094_1282719563"]={{"b7b6",1,"P,Karpov,Carlsen",""},{"f8b4",1,"D",""}},
["4199471513_247516615"]={{"g2g3",1,"P,Karpov,Carlsen",""}},
["3645375399_4272777241"]={{"c8b7",1,"P,Karpov,Carlsen",""}},
["4010613364_3291756277"]={{"f1g2",1,"P,Karpov,Carlsen",""}},
["1125062325_2598710649"]={{"f8e7",1,"P,Karpov,Carlsen",""}},
["719152549_1264145585"]={{"e1g1",1,"P,Karpov,Carlsen",""}},
["3446858030_3149551909"]={{"e8g8",1,"P,Karpov,Carlsen",""}},
["1046511901_3861246396"]={{"b1c3",1,"P,Karpov,Carlsen",""}},
["3930717995_1613908573"]={{"f6e4",1,"P,Karpov,Carlsen",""}},
["3666345467_2183750535"]={{"d1c2",1,"P,Karpov,Carlsen",""}},
["1776485553_668017003"]={{"e4c3",1,"P,Karpov,Carlsen",""}},
["1241572103_2590322391"]={{"c2c3",1,"P,Karpov,Carlsen",""}},
["716171560_651878221"]={{"c7c5",1,"P,Karpov,Carlsen",""}},
["4035854735_793249744"]={{"c1d2",1,"D",""}},
["2565967731_2330510460"]={{"d8e7",1,"D",""}},
["2321406402_500543344"]={{"g2g3",1,"D",""}},
["2841314300_3988261550"]={{"b8c6",1,"D",""}},
["3859681981_2943201969"]={{"f1g2",1,"D",""}},
["1242308220_4055673149"]={{"b4d2",1,"D",""}},
["1465736246_1739041083"]={{"b1d2",1,"D",""}},
["2562684592_3141598468"]={{"d7d6",1,"D",""}},
["2001272735_2145276802"]={{"e1g1",1,"D",""}},
["2431089428_2403163670"]={{"e8g8",1,"D",""}},
["3629946841_508937162"]={{"b1c3",5,"A,N,Fischer,Kasparov",""},{"g2g3",1,"N",""}},
["209054191_2554492971"]={{"f8g7",3,"A,Fischer,Kasparov",""},{"d7d5",2,"A,N,Fischer,Kasparov",""}},
["4098917676_2052824470"]={{"e2e4",3,"A,Fischer,Kasparov",""}},
["2715942436_1518540790"]={{"d7d6",3,"A,Fischer,Kasparov",""}},
["1310095115_2652748144"]={{"g1f3",1,"A,Fischer,Kasparov",""},{"f2f3",1,"A,Kasparov",""},{"f2f4",1,"A",""}},
["3637726404_2553878593"]={{"e8g8",1,"A,Fischer,Kasparov",""}},
["1755135029_744787128"]={{"f1e2",1,"A,Fischer,Kasparov",""}},
["2716751640_178336094"]={{"e7e5",1,"A,Fischer,Kasparov",""}},
["1221921740_3694337114"]={{"e1g1",1,"A,Fischer,Kasparov",""}},
["3961954181_3306302894"]={{"b8c6",1,"A,Fischer,Kasparov",""}},
["2742259396_2278004145"]={{"d4d5",1,"A,Fischer,Kasparov",""}},
["4252540444_970342753"]={{"c6e7",1,"A,Fischer,Kasparov",""}},
["3509552105_184867648"]={{"f3e1",1,"A,Fischer,Kasparov",""}},
["2849442177_1409725362"]={{"f6d7",1,"A,Fischer,Kasparov",""}},
["3956548677_2227883659"]={{"c1e3",1,"A,Fischer,Kasparov",""}},
["216847963_1389909064"]={{"f7f5",1,"A,Fischer,Kasparov",""}},
["3359960609_3852236993"]={{"e8g8",1,"A,Kasparov",""}},
["2013961936_1371663416"]={{"c1e3",1,"A,Kasparov",""}},
["2670881998_2278782715"]={{"e7e5",1,"A,Kasparov",""}},
["1980313626_1363237887"]={{"g1e2",1,"A,Kasparov",""}},
["3051897716_223685463"]={{"c7c6",1,"A,Kasparov",""}},
["4093009758_1001253200"]={{"d1d2",1,"A,Kasparov",""}},
["458468544_3082350341"]={{"b8d7",1,"A,Kasparov",""}},
["3153639719_928900713"]={{"e1c1",1,"A,Kasparov",""}},
["4216999399_3996673556"]={{"f8g7",1,"N",""}},
["58663204_203522985"]={{"f1g2",1,"N",""}},
["2944216549_1391499301"]={{"e8g8",1,"N",""}},
["523459860_3870100700"]={{"b1c3",1,"N",""}},
["3407487778_1622849341"]={{"d7d6",1,"N",""}},
["619555341_2753829307"]={{"g1f3",1,"N",""}},
["2989003202_2717956234"]={{"b8d7",1,"N",""}},
["310608933_585478630"]={{"e1g1",1,"N",""}},
["3060797548_1002733586"]={{"e7e5",1,"N",""}},
["1598770360_3981880598"]={{"e2e4",1,"N",""}},
["184170416_3448645494"]={{"c7c6",1,"N",""}},
["1290021786_4218873201"]={{"h2h3",1,"N",""}},
["2226359707_1427272827"]={{"d8b6",1,"N",""}},
["1532602357_2604741862"]={{"e8g8",1,"A",""}},
["3944208132_790405151"]={{"g1f3",1,"A",""}},
["2110975179_691536174"]={{"c7c5",1,"A",""}},
["328359903_1432088203"]={{"d4d5",1,"A",""}},
["1301892871_3947510363"]={{"e7e6",1,"A",""}},
["1666382354_3187943258"]={{"f1d3",1,"A",""}},
["3183236751_3671591449"]={{"e6d5",1,"A",""}},
["1806976197_2260614963"]={{"c4d5",1,"A",""}},
["1433122155_1528714632"]={{"b7b5",1,"A",""}},
["692214869_1003580177"]={{"c4d5",1,"A,Fischer,Kasparov",""},{"g1f3",1,"N,Kasparov",""}},
["396209659_3866165674"]={{"f6d5",1,"A,Fischer,Kasparov",""}},
["3857554377_2215018723"]={{"e2e4",1,"A,Fischer,Kasparov",""}},
["2958876865_2766015107"]={{"d5c3",1,"A,Fischer,Kasparov",""}},
["1154575533_1104935407"]={{"b2c3",1,"A,Fischer,Kasparov",""}},
["1606126895_3989913120"]={{"f8g7",1,"A,Fischer,Kasparov",""}},
["2812207596_264821661"]={{"g1f3",1,"A,Fischer,Kasparov",""}},
["828103203_166492844"]={{"c7c5",1,"A,Fischer,Kasparov",""}},
["1595631927_1972344073"]={{"c1e3",1,"A,Fischer,Kasparov",""}},
["3089341225_2744979402"]={{"d8a5",1,"A,Fischer,Kasparov",""}},
["461363196_3515138236"]={{"d1d2",1,"A,Fischer,Kasparov",""}},
["4091159650_1569834729"]={{"e8g8",1,"A,Fischer,Kasparov",""}},
["1133794451_3922481680"]={{"f1c4",1,"A,Fischer,Kasparov",""}},
["511776032_3095686514"]={{"b8c6",1,"A,Fischer,Kasparov",""}},
["3213322138_1039518240"]={{"f8g7",1,"N,Kasparov",""}},
["1201802073_3756797853"]={{"d1b3",1,"N,Kasparov",""}},
["2523200420_723491500"]={{"d5c4",1,"N,Kasparov",""}},
["2626441103_3133735697"]={{"b3c4",1,"N,Kasparov",""}},
["44550942_2202708348"]={{"e8g8",1,"N,Kasparov",""}},
["3001662447_924269957"]={{"e2e4",1,"N,Kasparov",""}},
["3881353447_399488997"]={{"c8g4",1,"N,Kasparov",""}},
["1705872416_1360339124"]={{"c1e3",1,"N,Kasparov",""}},
["2190835262_2265430647"]={{"f6d7",1,"N,Kasparov",""}},
["3231077370_1472972622"]={{"c4b3",1,"N,Kasparov",""}},
["2136657366_4209232486"]={{"d7b6",1,"N,Kasparov",""}},
["4073746784_1669197022"]={{"d4d5",2,"A,G,Tal,Kasparov",""}},
["2900058552_3714856974"]={{"e7e6",1,"A,Tal,Kasparov",""},{"b7b5",1,"A,G,Tal","Benko Gambit"}},
["2182141101_2283939087"]={{"b1c3",1,"A,Tal,Kasparov",""}},
["1446619803_238395118"]={{"e6d5",1,"A,Tal,Kasparov",""}},
["2150742225_1381215172"]={{"c4d5",1,"A,Tal,Kasparov",""}},
["3203287423_2415116671"]={{"d7d6",1,"A,Tal,Kasparov",""}},
["1360642128_1265463289"]={{"e2e4",1,"A,Tal,Kasparov",""}},
["78166872_1807082905"]={{"g7g6",1,"A,Tal,Kasparov",""}},
["1080356597_1795040552"]={{"g1f3",1,"A,Tal,Kasparov",""}},
["3600930106_1826259993"]={{"f8g7",1,"A,Tal,Kasparov",""}},
["780450297_2395169188"]={{"f1e2",1,"A,Tal,Kasparov",""}},
["3891778260_2819021890"]={{"e8g8",1,"A,Tal,Kasparov",""}},
["1471783461_475744443"]={{"e1g1",1,"A,Tal,Kasparov",""}},
["4081727084_91912527"]={{"f8e8",1,"A,Tal,Kasparov",""}},
["2618167085_3768302296"]={{"c4b5",1,"A,G,Tal","Benko Gambit"}},
["2852313722_3639720284"]={{"a7a6",1,"A,G,Tal","Benko Gambit"}},
["4191696673_414285663"]={{"b5a6",1,"A,G,Tal","Benko Gambit"}},
["4086315888_1798725871"]={{"c8a6",1,"A,G,Tal","Benko Gambit"}},
["1971121223_4135288733"]={{"b1c3",1,"A,G,Tal","Benko Gambit"}},
["2706739825_1886176380"]={{"d7d6",1,"A,G,Tal","Benko Gambit"}},
["1319246686_3035785978"]={{"e2e4",1,"A,G,Tal","Benko Gambit"}},
["454254678_2485837978"]={{"a6f1",1,"A,G,Tal","Benko Gambit"}},
["2259640661_976975607"]={{"e1f1",1,"A,G,Tal","Benko Gambit"}},
["3193139259_3671816753"]={{"g7g6",1,"A,G,Tal","Benko Gambit"}},
["4204733846_3683695232"]={{"g2g3",1,"A,G,Tal","Benko Gambit"}},
["3650748328_738008926"]={{"f8g7",1,"A,G,Tal","Benko Gambit"}},
["566006635_3387226851"]={{"f1g2",1,"A,G,Tal","Benko Gambit"}},
["2002712443_2676602819"]={{"e8g8",1,"A,G,Tal","Benko Gambit"}},
["1936149339_3682643453"]={{"b1c3",1,"N",""}},
["2806920557_1570182684"]={{"b8d7",1,"N",""}},
["132456586_3715243888"]={{"e2e4",1,"N",""}},
["1381260162_4255814928"]={{"e7e5",1,"N",""}},
["3144615766_725137428"]={{"g1f3",1,"N",""}},
["766131353_756816165"]={{"f8e7",1,"N",""}},
["1148735369_4238369005"]={{"f1e2",1,"N",""}},
["2366317732_3664108811"]={{"e8g8",1,"N",""}},
["1027953749_1849182706"]={{"e1g1",1,"N",""}},
["2578890780_1998157830"]={{"c7c6",1,"N",""}},
["2206587602_590303517"]={{"g2g3",2,"A,D,Fischer",""}},
["2692940012_3544380611"]={{"g8f6",2,"A,D,Fischer",""}},
["1423678724_3357202841"]={{"f1g2",2,"A,D,Fischer",""}},
["4175008197_2529935893"]={{"g7g6",1,"A,Fischer",""},{"e7e6",1,"D",""}},
["3155543144_2541748900"]={{"g1f3",1,"A,Fischer",""}},
["718340007_2443486101"]={{"f8g7",1,"A,Fischer",""}},
["3539309412_1941784104"]={{"e1g1",1,"A,Fischer",""}},
["895096815_2203995068"]={{"e8g8",1,"A,Fischer",""}},
["3326638044_3737248549"]={{"c2c4",1,"A,Fischer",""}},
["3458372283_314715297"]={{"d7d6",1,"A,Fischer",""}},
["567614356_3596386855"]={{"b1c3",1,"A,Fischer",""}},
["4126959010_1347107270"]={{"d8e8",1,"A,Fischer",""}},
["3591513296_3280330516"]={{"g1f3",1,"D",""}},
["1087840031_3315695141"]={{"f8e7",1,"D",""}},
["688221199_337446893"]={{"e1g1",1,"D",""}},
["3467307140_3841854073"]={{"e8g8",1,"D",""}},
["1035503799_3110183648"]={{"c2c4",1,"D",""}},
["902983120_1969384804"]={{"d7d5",1,"D",""}},
["283498602_3606150750"]={{"b1c3",1,"D",""}},
["3301746268_1357301183"]={{"c7c6",1,"D",""}},
["2194848374_1713244088"]={{"d1c2",1,"D",""}},
["834028348_3286648148"]={{"d8e8",1,"D",""}},
["2360198844_3140603041"]={{"g8f6",1,"P,Carlsen",""}},
["2029345620_2691293691"]={{"e2e3",1,"P,Carlsen",""}},
["3303043550_2443264723"]={{"c7c5",1,"P,Carlsen",""}},
["2862662346_3988958582"]={{"c2c3",1,"P,Carlsen",""}},
["834971824_1049469433"]={{"b8c6",1,"P,Carlsen",""}},
["2123479537_2086148582"]={{"b1d2",1,"P,Carlsen",""}},
["2779623229_420144152"]={{"e7e6",1,"P,Carlsen",""}},
["2338724392_1279588633"]={{"g1f3",1,"P,Carlsen",""}},
["497230311_1247828008"]={{"f8d6",2,"P,Carlsen",""}},
["1953722585_1466163277"]={{"f4g3",2,"P,Carlsen",""}},
["1742022016_2949497458"]={{"e8g8",2,"P,Carlsen",""}},
["3617281393_462444171"]={{"f1d3",2,"P,Carlsen",""}},
["158726636_2135718856"]={{"d8c7",1,"P,Carlsen",""}},
["1573056238_66777793"]={{"e7e6",1,"P",""}},
["1929993211_1454698432"]={{"e2e3",1,"P",""}},
["3474747761_1736199400"]={{"c7c5",1,"P",""}},
["2707210853_455058253"]={{"c2c3",1,"P",""}},
["976791583_3360731074"]={{"b8c6",1,"P",""}},
["1970125150_2323978205"]={{"g1f3",1,"P",""}},
["3819471505_2359408364"]={{"d7d5",1,"P",""}},
["3332323115_791848406"]={{"b1d2",1,"P",""}},
["3549152206_3585642711"]={{"f6e4",1,"A,Morphy",""}},
["3812999454_933476621"]={{"g5f4",1,"A,Morphy",""}},
["4056821427_3071460191"]={{"d7d5",1,"A,Morphy",""}},
["3573127945_344051813"]={{"e2e3",1,"A,Morphy",""}},
["1760342403_625570637"]={{"c7c5",1,"A,Morphy",""}},
["111936151_1495964904"]={{"f1d3",1,"A,Morphy",""}},
["3628248586_1039577515"]={{"b8c6",1,"A,Morphy",""}},
["2534915915_2133002676"]={{"c2c3",1,"A,Morphy",""}},
["208917809_2892760379"]={{"d8b6",1,"A,Morphy",""}},
["1943064277_725688784"]={{"d1c2",1,"A,Morphy",""}},
["3233036191_2394514236"]={{"c8d7",1,"A,Morphy",""}},
["3545248910_1844597678"]={{"g8f6",1,"P,Capablanca",""}},
["654879078_1990885108"]={{"e2e3",1,"P,Capablanca",""}},
["2602402796_1197661660"]={{"e7e6",1,"P,Capablanca",""}},
["3050714873_304922845"]={{"f1d3",1,"P,Capablanca",""}},
["1798871652_1995500958"]={{"c7c5",1,"P,Capablanca",""}},
["91761008_177406523"]={{"c2c3",1,"P,Capablanca",""}},
["2652652298_3655077556"]={{"b8c6",1,"P,Capablanca",""}},
["3511243339_2601105067"]={{"b1d2",1,"P,Capablanca",""}},
["175457415_4267395925"]={{"f8d6",1,"P,Capablanca",""}},
["1671763385_3814257456"]={{"e1g1",1,"P,Capablanca",""}},
["2215285042_331087524"]={{"e8g8",1,"P,Capablanca",""}},
["1998123265_1311004221"]={{"d4c5",1,"P,Capablanca",""}},
["438085820_1852213273"]={{"d6c5",1,"P,Capablanca",""}},
["3615004527_2000134405"]={{"b2b4",1,"P,Capablanca",""}},
["1340480131_443656152"]={{"c5d6",1,"P,Capablanca",""}},
["37690588_3577310670"]={{"e7e6",1,"N",""}},
["754231753_2155311311"]={{"c1g5",1,"N",""}},
["1803898132_2261920999"]={{"h7h6",1,"N",""}},
["791283199_2637141141"]={{"g5h4",1,"N",""}},
["163607839_3943777134"]={{"d7d5",1,"N",""}},
["754434213_1216499796"]={{"e2e3",1,"N",""}},
["2430790191_2034955132"]={{"f8e7",1,"N",""}},
["4180711743_2834729652"]={{"b1d2",1,"N",""}},
["571248627_3450107722"]={{"e8g8",1,"N",""}},
["2453864194_2046419891"]={{"f1d3",1,"N",""}},
["1286362015_489017072"]={{"b7b6",1,"N",""}},
["2445046135_3988867454"]={{"g8f6",1,"A",""}},
["1709501599_4137247780"]={{"c1g5",1,"A",""}},
["580192322_4030478348"]={{"b8d7",1,"A",""}},
["2185108901_1893282144"]={{"f2f3",1,"A",""}},
["74220687_190378193"]={{"c7c6",1,"A",""}},
["1114806437_1033908950"]={{"e2e4",1,"A",""}},
["398713773_494450870"]={{"d5e4",1,"A",""}},
["6143341_1241027637"]={{"f3e4",1,"A",""}},
["4099436182_3369113651"]={{"h7h6",1,"A",""}},
["2968987261_3542949953"]={{"g5h4",1,"A",""}},
["2518505117_2769549242"]={{"g7g5",1,"A",""}},
["1974181536_3381407359"]={{"d4e5",1,"A,G","Budapest Gambit"}},
["2918822772_3916999007"]={{"f6g4",1,"A,G","Budapest Gambit"}},
["848421164_3627591862"]={{"c1f4",1,"A,G","Budapest Gambit"}},
["4222167249_148870792"]={{"b8c6",1,"A,G","Budapest Gambit"}},
["3036428688_1242181271"]={{"g1f3",1,"A,G","Budapest Gambit"}},
["574161503_1278119846"]={{"f8b4",1,"A,G","Budapest Gambit"}},
["4129886078_789722941"]={{"b1d2",1,"A,G","Budapest Gambit"}},
["756357554_1245760195"]={{"d8e7",1,"A,G","Budapest Gambit"}},
["1069108995_3715998159"]={{"e2e3",1,"A,G","Budapest Gambit"}},
["2209113481_3971285735"]={{"g4e5",1,"A,G","Budapest Gambit"}},
["1964044885_1480952"]={{"e7e5",2,"P,N,Carlsen",""},{"c7c5",1,"N,Karpov",""}},
["2620108417_3599021564"]={{"b1c3",2,"P,N,Carlsen",""}},
["1208144055_1351814685"]={{"g8f6",1,"N,Carlsen",""},{"b8c6",1,"P",""}},
["3160034655_1271604039"]={{"g1f3",1,"N,Carlsen",""}},
["715093648_1307542134"]={{"b8c6",1,"N,Carlsen",""}},
["1707763665_255474281"]={{"g2g3",1,"N,Carlsen",""}},
["1187823087_4283932599"]={{"d7d5",1,"N,Carlsen",""}},
["1677396053_1556384909"]={{"c4d5",1,"N,Carlsen",""}},
["1562704379_2170873398"]={{"f6d5",1,"N,Carlsen",""}},
["2941571017_3809699711"]={{"f1g2",1,"N,Carlsen",""}},
["56017672_3183639795"]={{"d5b6",1,"N,Carlsen",""}},
["3822994154_1541534283"]={{"e1g1",1,"N,Carlsen",""}},
["74565217_2869100511"]={{"f8e7",1,"N,Carlsen",""}},
["1839445361_2059306519"]={{"a2a3",1,"N,Carlsen",""}},
["467860929_3473212012"]={{"e8g8",1,"N,Carlsen",""}},
["3908083186_2459609845"]={{"b2b4",1,"N,Carlsen",""}},
["1886261278_4292652072"]={{"f7f5",1,"N,Carlsen",""}},
["458244417_2088073053"]={{"g1f3",1,"N,Karpov",""}},
["2375383694_2052183660"]={{"g8f6",1,"N,Karpov",""}},
["2043537254_1628044086"]={{"b1c3",1,"N,Karpov",""}},
["2917439824_3877519575"]={{"b8c6",1,"N,Karpov",""}},
["3803285521_2781608136"]={{"g2g3",1,"N,Karpov",""}},
["3250016815_1436966166"]={{"g7g6",1,"N,Karpov",""}},
["2239432578_1424858535"]={{"f1g2",1,"N,Karpov",""}},
["695798595_171738667"]={{"f8g7",1,"N,Karpov",""}},
["3512493952_3894764438"]={{"e1g1",1,"N,Karpov",""}},
["921953035_415657474"]={{"e8g8",1,"N,Karpov",""}},
["3319890744_1163511451"]={{"d2d4",1,"N,Karpov",""}},
["3627626225_1091137602"]={{"c5d4",1,"N,Karpov",""}},
["3347914520_3920333007"]={{"f3d4",1,"N,Karpov",""}},
["794325996_93949118"]={{"c6d4",1,"N,Karpov",""}},
["863903520_3822488269"]={{"d1d4",1,"N,Karpov",""}},
["3578013690_1725082567"]={{"d7d6",1,"N,Karpov",""}},
["984854229_2722891073"]={{"c1g5",1,"N,Karpov",""}},
["2109884936_2766756201"]={{"c8e6",1,"N,Karpov",""}},
["123191798_306624002"]={{"g2g3",1,"P",""}},
["609295304_3794473948"]={{"g7g6",1,"P",""}},
["1620921957_3814773613"]={{"f1g2",1,"P",""}},
["3432989348_3182545121"]={{"f8g7",1,"P",""}},
["884616807_1604857180"]={{"d2d3",1,"P",""}},
["1274245267_2579582467"]={{"d7d6",1,"P",""}},
["2751789500_1566564485"]={{"e2e4",1,"P",""}},
["4055204532_2106026725"]={{"g8e7",1,"P",""}},
["2219256779_1190203860"]={{"g1e2",1,"P",""}},
["1202084005_451240316"]={{"e8g8",1,"P",""}},
["4159187028_2931357061"]={{"e1g1",1,"P",""}},
["3955174653_3392271949"]={{"d7d5",2,"P,N,Fischer,Carlsen,Capablanca",""}},
["3465058631_1772283255"]={{"c2c4",1,"N,Carlsen",""},{"g2g3",1,"P,Fischer,Capablanca",""}},
["3336731680_2778802931"]={{"e7e6",1,"N,Carlsen",""}},
["3895052597_4042209266"]={{"g2g3",1,"N,Carlsen",""}},
["3408859915_8557100"]={{"g8f6",1,"N,Carlsen",""}},
["1064799971_467320694"]={{"f1g2",1,"N,Carlsen",""}},
["2473951778_1158391034"]={{"f8e7",1,"N,Carlsen",""}},
["4205310258_2495077682"]={{"e1g1",1,"N,Carlsen",""}},
["487093689_1683280038"]={{"e8g8",1,"N,Carlsen",""}},
["3994686858_969635903"]={{"b2b3",1,"N,Carlsen",""}},
["2616678495_1869382657"]={{"c7c5",1,"N,Carlsen",""}},
["4122471243_319777700"]={{"c1b2",1,"N,Carlsen",""}},
["774596418_446939715"]={{"b8c6",1,"N,Carlsen",""}},
["3985523577_2580496553"]={{"g8f6",1,"P,Fischer,Capablanca",""}},
["433512081_2190962163"]={{"f1g2",1,"P,Fischer,Capablanca",""}},
["3050623568_3695605375"]={{"c7c6",1,"P,Fischer,Capablanca",""}},
["4090154618_3938366584"]={{"e1g1",1,"P,Fischer,Capablanca",""}},
["342182641_442350060"]={{"c8g4",1,"P,Fischer,Capablanca",""}},
["2526021174_1552363197"]={{"d2d3",1,"P,Fischer,Capablanca",""}},
["3923335362_2599308770"]={{"b8d7",1,"P,Fischer,Capablanca",""}},
["1232227621_436946062"]={{"b1d2",1,"P,Fischer,Capablanca",""}},
["2454608873_2136586608"]={{"e7e5",1,"P,Fischer,Capablanca",""}},
["2071267133_2848691316"]={{"e2e4",1,"P,Fischer,Capablanca",""}},
["1748355020_3377060586"]={{"d7d5",1,"A",""}},
["1292006006_1792723408"]={{"g1f3",1,"A",""}},
["3687270841_1828612321"]={{"g8f6",1,"A",""}},
["799003729_2007385531"]={{"e2e3",1,"A",""}},
["2475359963_1181673107"]={{"g7g6",1,"A",""}},
["3611732854_1193616930"]={{"f1e2",1,"A",""}},
["506839131_1642109892"]={{"f8g7",1,"A",""}},
["3859852440_2214166137"]={{"e1g1",1,"A",""}},
["29304851_1931113453"]={{"e8g8",1,"A",""}},
["4071442464_780524404"]={{"d2d3",1,"A",""}},
["2380535508_3907827755"]={{"c7c5",1,"A",""}},
["144136935_2595400514"]={{"e7e5",1,"N",""}},
["3786147379_1277199942"]={{"c1b2",1,"N",""}},
["976259642_1166815137"]={{"b8c6",1,"N",""}},
["1969593211_123312062"]={{"e2e3",1,"N",""}},
["3379606001_915485846"]={{"d7d5",1,"N",""}},
["3964077131_2499946412"]={{"f1b5",1,"N",""}},
["2645593138_182963977"]={{"f8d6",1,"N",""}},
["4099988748_400848748"]={{"f2f4",1,"N",""}},
["3777957362_314112762"]={{"d8h4",1,"N",""}},
["623003121_3725997279"]={{"g2g3",1,"N",""}},
["103063503_779849985"]={{"h4e7",1,"N",""}},
["1279738864_588983404"]={{"g1f3",1,"N",""}},
["3665983551_624921949"]={{"c8g4",1,"N",""}},
}

local BOOKNAMES = {
list={"Vienna Game: Falkbeer Variation","Benko Gambit","Scotch Gambit","Modern Defence","Sicilian Defence: Alapin Variation","Queen's Gambit Declined: Orthodox Defence","Caro-Kann: Classical, Bronstein-Larsen","Italian Game: Two Knights, Fried Liver","Caro-Kann Defence: Two Knights Attack","Sicilian Defence: Moscow Variation","Reti Opening: Reti Gambit","Petrov's Defence: Classical Attack","Centre Game","Italian Game: Evans Gambit","Caro-Kann: Martian Gambit, Qh5+ trap","Scandinavian Defence: Modern Variation","French Defence: Tarrasch Variation","London System","Sicilian: Grand Prix Attack","Vienna Gambit","Ruy Lopez: Exchange Variation","Sicilian: Najdorf, Opocensky","Bishop's Opening","Caro-Kann Defence: Panov-Botvinnik Attack","Queen's Indian Defence","Semi-Slav Defence: Botvinnik Variation","Sicilian Defence: Accelerated Dragon","Pirc Defence: 150 Attack","Ruy Lopez: Marshall Attack","Philidor Defence: Hanham Variation","Scandinavian Defence: Main Line","Queen's Gambit Declined: Tarrasch Defence","French Defence: Exchange Variation","Sicilian: Dragon, Yugoslav Attack","Sicilian Defence: Sveshnikov Variation","Falkbeer Counter Gambit","Queen's Gambit Accepted: Classical","Italian Game: Two Knights, Traxler-line","Caro-Kann: Alien Gambit declined with ...e6","Sicilian Defence: Smith-Morra Gambit","English Opening: Four Knights","Caro-Kann Defence: Exchange Variation","French: Winawer, Poisoned Pawn","Ruy Lopez: Closed","French Defence: Classical Variation","Caro-Kann Defence: Advance Variation","Colle System","Ruy Lopez: Closed, Chigorin","Ruy Lopez: Berlin, Rio de Janeiro","French Defence: Advance Variation","Caro-Kann Defence: Classical Variation","King's Gambit Accepted","Caro-Kann: Martian Gambit, Ne6 sacrifice","Catalan Opening: Open Defence","Four Knights Game: Scotch Variation","Sicilian Defence: Kan Variation","Ruy Lopez: Schliemann Defence","Nimzo-Indian Defence: Rubinstein System","French Defence","Nimzo-Larsen Attack","Caro-Kann Defence: Fantasy Variation","Slav Defence: Czech Variation","Ruy Lopez: Open","Reti Opening","Italian Game: Two Knights Defence","Italian Game: Two Knights, Max Lange","Ruy Lopez: Morphy Defence","Four Knights Game: Spanish Variation","Nimzo-Indian Defence: Samisch Variation","Semi-Slav Defence: Meran Variation","Alekhine's Defence: Modern Variation","English Opening: King's English","Trompowsky Attack","Sicilian Defence: Closed","Queen's Gambit Accepted","Scotch Game: Mieses Variation","Sicilian: Accelerated Dragon, Maroczy Bind","Caro-Kann: Alien Gambit, 7...Kg8","Richter-Veresov Attack","Ruy Lopez: Breyer Variation","Bird Opening","Gruenfeld Defence: Exchange Variation","Sicilian Defence: Scheveningen Variation","Nimzowitsch Defence","Caro-Kann: Martian Gambit declined with ...e6","Nimzo-Indian Defence: Classical Variation","Gruenfeld Defence: Russian System","Sicilian: Richter-Rauzer","Ruy Lopez: Classical Defence","Sicilian Defence: Taimanov Variation","Ruy Lopez: Steinitz Defence","Torre Attack","Scotch Game: Classical Variation","English Opening: Reversed Sicilian","Sicilian: Najdorf, Poisoned Pawn setup","King's Gambit: Muzio Gambit","King's Pawn Game","Queen's Gambit Declined: Exchange Variation","Sicilian: Najdorf, English Attack","Petrov's Defence: Cochrane Gambit","Budapest Gambit","Four Knights Game","Italian Game","Queen's Gambit Declined","Danish Gambit","Pirc Defence: Classical Variation","King's Indian Defence: Fianchetto Variation","Sicilian Defence: Najdorf Variation","Vienna Game","Pirc Defence","Caro-Kann: Advance, Short Variation","Sicilian Defence: Open","Indian Defence","Bogo-Indian Defence","King's Gambit: Kieseritzky Gambit","King's Gambit","Caro-Kann: Alien Gambit, Nxf7 sacrifice","French Defence: Winawer Variation","Caro-Kann Defence: Karpov Variation","King's Gambit Declined: Classical","Caro-Kann Defence","Sicilian Defence: Dragon Variation","King's Indian Defence: Classical Variation","Italian Game: Giuoco Pianissimo","King's Indian Defence","Alekhine's Defence","Dutch Defence: Stonewall Variation","English Opening: Symmetrical Variation","King's Indian Defence: Four Pawns Attack","Sicilian Defence: Nimzowitsch-Rossolimo Attack","Ruy Lopez: Berlin, Anti-Berlin","Benoni Defence: Modern Variation","Petrov's Defence","Ruy Lopez: Berlin Defence","Pirc Defence: Austrian Attack","Old Indian Defence","Slav Defence","Catalan Opening","Ponziani Opening","Dutch Defence","King's Indian Attack","Sicilian Defence","Gruenfeld Defence","King's Indian Defence: Saemisch Variation","Scotch Game","Dutch Defence: Leningrad Variation","English Opening","Queen's Gambit","King's Knight Opening","Ruy Lopez","Scandinavian Defence","Nimzo-Indian Defence","Caro-Kann: Martian Gambit","Philidor Defence","Caro-Kann: Alien Gambit","Italian Game: Giuoco Piano","Open Game","Queen's Pawn Game","Closed Game"},
at={["2764148308_878960369"]=1,["3403392197_1982343012"]=1,["3650748328_738008926"]=2,["3932144020_1606704354"]=3,["2988707716_1229347758"]=4,["699869372_1488524140"]=5,["3028676344_570925301"]=6,["2530367402_1489522329"]=7,["3305824193_1084532664"]=8,["1554475048_2246324185"]=9,["383142334_601698190"]=10,["3994686858_969635903"]=11,["1890578094_574057075"]=12,["4247475671_1705917951"]=13,["2995402786_1145986629"]=14,["387477184_1120671648"]=15,["3836169339_2821551887"]=16,["3855865744_2064816128"]=17,["932856144_2311040904"]=18,["3027739608_1100806174"]=19,["2009969739_3922864585"]=14,["2644735585_2659898646"]=20,["143199881_39812741"]=21,["1038618714_3280648907"]=22,["401912385_3055976831"]=23,["1745619183_3408007303"]=24,["614354094_1282719563"]=25,["3726609563_3725824253"]=26,["829313241_2513740035"]=27,["3875496916_1513698390"]=17,["2787087532_3318604745"]=28,["1461824584_935018140"]=29,["719152549_1264145585"]=25,["4138233814_2433260959"]=30,["2329290930_3083445522"]=31,["3894041467_3453498081"]=32,["2540095318_3188208272"]=19,["541556865_3668893162"]=33,["53293052_2089643573"]=34,["1700689324_3600788345"]=35,["2470842476_2017239529"]=32,["1332254654_4000339793"]=36,["1742594032_1482001857"]=37,["583588607_192143540"]=38,["566006635_3387226851"]=2,["414381912_2372098804"]=39,["1643239533_91682675"]=3,["2026131472_2852325139"]=40,["715093648_1307542134"]=41,["294341240_1615508826"]=17,["3142500296_4198939635"]=42,["1037784602_3021967190"]=43,["1966156715_1489506985"]=44,["1508886111_2242555757"]=45,["2263065702_3213670257"]=22,["2692399348_4108559366"]=46,["3058733259_763232015"]=38,["2215285042_331087524"]=47,["295095992_3228891544"]=48,["2657070559_392920461"]=49,["1175355931_1610124957"]=50,["896623973_577042667"]=51,["598085746_3568055398"]=52,["2269257780_2883384150"]=6,["2383859979_3536124176"]=53,["429135993_3388330932"]=54,["699942380_29325486"]=36,["653133675_643930410"]=55,["3897339941_3075329825"]=10,["1228276241_2818094027"]=37,["2606450461_2225817313"]=56,["2326852144_169980203"]=57,["1069975193_229634931"]=58,["3226991920_3251485640"]=21,["467170534_3184752324"]=59,["483037430_2488960028"]=55,["3379606001_915485846"]=60,["2344005878_3903036002"]=26,["862917209_4121887659"]=13,["2027264077_2958551491"]=30,["2103990420_3106313865"]=8,["1373586636_2442499471"]=52,["871595122_3554630604"]=61,["1757585310_1561920198"]=62,["2079474030_1210878113"]=17,["88032469_1494733543"]=30,["4119111957_1952518534"]=6,["3551888371_447844566"]=63,["3465058631_1772283255"]=64,["1163715901_3869118912"]=65,["2806991418_2400029438"]=32,["2029345620_2691293691"]=18,["2456776457_2386585870"]=66,["1775551159_3251180726"]=67,["1103114120_3255877520"]=68,["3666345467_2183750535"]=25,["1083238899_3900326820"]=69,["858057322_1666602654"]=19,["797684098_1858107071"]=70,["3734804503_4267017688"]=71,["1704989525_2660931248"]=24,["884616807_1604857180"]=72,["111936151_1495964904"]=73,["3672114653_2434979568"]=43,["1185956272_2655697043"]=26,["1535189885_2184785354"]=67,["3994705864_427993625"]=74,["629864490_729753805"]=75,["3574630371_2021402549"]=48,["1462840330_616234770"]=54,["2618167085_3768302296"]=2,["2476645128_1594414487"]=70,["1242483029_4154472487"]=76,["503094944_1261694772"]=43,["2602461404_2529015838"]=24,["639183715_1843139065"]=77,["438448434_3700406576"]=5,["3554611104_2001322005"]=78,["2549951040_1678987354"]=7,["1704675504_2636419126"]=46,["4073570227_3796130030"]=3,["398713773_494450870"]=79,["2588251810_984194986"]=80,["3687270841_1828612321"]=81,["1665976543_2965236596"]=14,["3341784484_2264588873"]=23,["2566300772_3275377017"]=12,["2958876865_2766015107"]=82,["1966216710_3383456287"]=6,["901576427_3344541755"]=83,["2661456336_2122783900"]=38,["1954534204_1293586992"]=84,["743622232_3886448276"]=85,["3416599755_2847080821"]=45,["2447209771_3497613431"]=31,["975821802_734524224"]=86,["2139161708_3197753002"]=51,["883380271_184103102"]=17,["3520226754_807863703"]=75,["143234367_2145611048"]=63,["3076108724_2894156131"]=71,["2734241656_114875155"]=5,["1873164116_2161155506"]=83,["527974280_162482764"]=57,["2523200420_723491500"]=87,["891272976_2638615470"]=58,["3641096674_3378848031"]=16,["3297407814_3602657495"]=5,["3573127945_344051813"]=73,["2948717619_481899536"]=88,["3617281393_462444171"]=18,["395942743_3130936558"]=14,["2969427683_1863767315"]=89,["1760342403_625570637"]=73,["3426615939_2174939700"]=90,["3822713847_1212793124"]=91,["1803898132_2261920999"]=92,["3919386614_656259751"]=37,["3948080526_1787668767"]=91,["633951351_3887188308"]=55,["469145827_3585674838"]=93,["2238434329_1643831245"]=30,["3160034655_1271604039"]=94,["1269928575_1178050176"]=15,["4236035497_4260572781"]=26,["2039338638_2832372512"]=35,["1587121158_2352351946"]=57,["3884082111_3578732261"]=32,["4049834942_3784725684"]=95,["1137834240_3804833912"]=66,["2133496676_2240199975"]=96,["3181594810_1110982368"]=57,["3408859915_8557100"]=11,["1455639289_3423785943"]=58,["684420154_3972914460"]=97,["2267961938_3236147296"]=50,["2858601199_2497002864"]=63,["2402235114_1195019315"]=17,["2305462975_3164535553"]=98,["792556611_3072313273"]=99,["3257072904_771082985"]=100,["1295364472_2554548821"]=37,["1296067649_1506142341"]=45,["658790447_612118511"]=40,["221487568_1480210388"]=3,["2559900928_3786091994"]=57,["975412766_1978607406"]=43,["848421164_3627591862"]=101,["631516469_2690218932"]=31,["350661959_3901460960"]=46,["4129886078_789722941"]=101,["940702142_3823206285"]=102,["1165319123_803657300"]=103,["1274245267_2579582467"]=72,["3963488605_2409776439"]=5,["1533653089_3251731635"]=90,["1843800864_3100480321"]=104,["3701143054_3375731523"]=105,["633395710_3776960161"]=30,["1345860765_2212251336"]=17,["2546856114_313470911"]=35,["2844045951_3332570842"]=106,["2901765106_820923863"]=66,["1290021786_4218873201"]=107,["2796262303_1339762579"]=108,["3012321721_3369112292"]=95,["620637535_3420586837"]=55,["3913564067_3099424667"]=51,["444548174_2888391573"]=66,["366563032_3158854649"]=109,["242691836_2662579752"]=58,["3342656789_676557722"]=110,["2783350703_4135182694"]=37,["1244383243_1451000414"]=111,["4187595252_2035262407"]=76,["1452770549_1730644433"]=90,["230252057_3912747428"]=29,["1556166185_981552715"]=84,["1974181536_3381407359"]=101,["1037431278_4276515674"]=112,["2713773920_414943030"]=73,["3076256110_3887918965"]=86,["1175289867_933231277"]=49,["2499421971_3541945599"]=113,["451397213_2813263403"]=78,["336543281_2330303861"]=16,["2941571017_3809699711"]=41,["3859681981_2943201969"]=114,["1696967646_3684597201"]=115,["3627342620_699935831"]=70,["1759584392_3538999536"]=88,["3617797380_2440977701"]=96,["3569344528_1057193358"]=116,["1905183658_3078628663"]=45,["3572465621_1504545215"]=26,["751841937_2059599312"]=9,["824909897_4050088408"]=8,["503612476_1592470749"]=99,["1926630054_3285254023"]=117,["1637868470_549766402"]=55,["3723169625_1007573625"]=55,["2656791352_2495497830"]=51,["1664376627_4070252570"]=104,["3176476189_172411030"]=62,["1055899996_507536894"]=118,["1131725050_3054912687"]=8,["3207812307_1619173095"]=71,["2669409696_3563006871"]=112,["487022551_692408713"]=115,["2366013103_413419270"]=119,["1399617849_1429066908"]=68,["3303043550_2443264723"]=18,["4095454857_3096642540"]=42,["3879053413_354225753"]=15,["1149635856_565034946"]=61,["1912778573_3666381752"]=120,["2396428288_3875564427"]=17,["2440675002_1937444941"]=29,["3567070473_1455064951"]=62,["1930288601_3731204546"]=121,["4069201443_2577989252"]=56,["3388874096_1079186264"]=15,["2981964649_2396004641"]=122,["1355822682_2507208631"]=58,["716171560_651878221"]=25,["2918822772_3916999007"]=101,["1483395251_1307213869"]=20,["1755135029_744787128"]=123,["662831004_373032709"]=55,["2539980411_3269838958"]=23,["428705941_3144738714"]=124,["4197053141_1242901868"]=76,["2471063607_347479184"]=41,["1733487666_1614977624"]=44,["3060797548_1002733586"]=107,["3122719190_1146433851"]=15,["193422607_66594076"]=49,["1842017842_1385781556"]=24,["2960779443_546705028"]=86,["4277888928_3555392071"]=48,["285731677_1642827787"]=30,["209054191_2554492971"]=125,["1856101152_3984312706"]=7,["3890295189_4222476028"]=85,["1451473111_313543547"]=38,["3050623568_3695605375"]=64,["4205310258_2495077682"]=11,["4098917676_2052824470"]=125,["3290647750_448829819"]=69,["401601338_3633330238"]=71,["1124731779_1295465854"]=17,["3427361878_4172894935"]=102,["2065421292_766261439"]=83,["1433062973_2566939915"]=100,["3743654643_3301932781"]=126,["892220082_2625202894"]=58,["1035503799_3110183648"]=127,["2953658622_440603159"]=15,["3446858030_3149551909"]=25,["583855510_1353725705"]=3,["1429071704_3507807451"]=70,["3191430669_720251601"]=58,["2109884936_2766756201"]=128,["2033621088_3982713565"]=51,["1806976197_2260614963"]=129,["992889991_2774822616"]=51,["2097009758_146316229"]=111,["3645436577_613061839"]=50,["1663164618_3089720726"]=33,["195942228_2577854743"]=105,["403256009_4098994625"]=50,["2917439824_3877519575"]=128,["3500085894_1798748097"]=105,["2180683932_2412203240"]=35,["2854234228_1257309059"]=130,["1239839175_2080675624"]=68,["975316267_2926065512"]=12,["1584851663_3871744088"]=40,["1439950506_164689673"]=35,["2596708996_2622929967"]=44,["1639805275_1029219472"]=6,["1988243496_543302923"]=39,["541264184_1843468490"]=131,["4226576505_3381541768"]=36,["3923895959_1935601102"]=74,["3615956343_2970946307"]=29,["415259277_1638898661"]=20,["1460187493_1705119511"]=37,["1928331501_794733307"]=29,["780450297_2395169188"]=132,["680147524_2543008005"]=85,["1975332879_2754315249"]=14,["3018904586_2269763314"]=83,["564414734_3091100876"]=67,["1286362015_489017072"]=92,["871502089_1269970400"]=35,["70539312_1769073289"]=104,["3995699140_83655980"]=32,["4102537171_1824920525"]=16,["2348534932_3209658784"]=9,["1540214859_3646739849"]=96,["4195712532_4012722975"]=84,["2457650856_1603386492"]=92,["2094683841_4132427200"]=130,["74220687_190378193"]=79,["545391177_2041141164"]=58,["239111981_3942727455"]=5,["270270436_2467187447"]=5,["1876490418_1763613301"]=22,["875328328_4074824490"]=78,["3486224055_2109408921"]=5,["576831495_1447332823"]=112,["1567304802_604598833"]=130,["3890732443_2529346961"]=133,["1287370793_1282292534"]=96,["1710787021_3974325773"]=70,["1273882536_336271524"]=6,["4126936459_4259815949"]=20,["1527795581_218564162"]=105,["44550942_2202708348"]=87,["4071442464_780524404"]=81,["2053147514_183509341"]=134,["119033572_3596482886"]=31,["2994619542_662406624"]=13,["2037713137_3573800004"]=100,["357671744_101697628"]=21,["1129085005_1156739983"]=23,["1562704379_2170873398"]=41,["426643220_3373304082"]=50,["4073746784_1669197022"]=132,["2070980779_2732199097"]=37,["3880152175_1941485642"]=13,["3671122500_362291208"]=22,["1748355020_3377060586"]=81,["1089478713_3658705410"]=135,["3193568943_2953286473"]=110,["3679417110_2425919872"]=120,["4122319670_2629596095"]=24,["69410211_2508096360"]=26,["4204028796_2843793441"]=32,["969319238_1483515825"]=93,["4063480439_3838875369"]=63,["2806920557_1570182684"]=136,["3674825903_67310401"]=131,["1215707678_1770130692"]=63,["500872505_617324647"]=21,["1446619803_238395118"]=132,["1566578436_2945949764"]=45,["2636434883_2533973549"]=137,["1574143659_2379805992"]=4,["2438835551_3124607908"]=138,["4274443574_2824923078"]=20,["2219256779_1190203860"]=72,["3039263490_312857089"]=69,["980486394_1990651117"]=87,["3542449381_3951408537"]=58,["2092035159_1717482890"]=24,["1440784683_2038028521"]=21,["2380535508_3907827755"]=81,["4270150132_3284438665"]=112,["404497482_238053888"]=124,["1262051440_2178756235"]=24,["3485341899_2554899864"]=124,["3852145122_1933923345"]=12,["3843921247_2709360132"]=54,["1351362020_1378431100"]=139,["4107142094_2722949941"]=20,["1156536892_1522086120"]=25,["2692940012_3544380611"]=140,["158726636_2135718856"]=18,["3857554377_2215018723"]=82,["948161529_2120592359"]=126,["3304124008_4270709814"]=105,["1606126895_3989913120"]=82,["409474084_1199551250"]=138,["2862662346_3988958582"]=18,["2559175764_90498165"]=69,["1812412823_3984989613"]=4,["2234632388_957074640"]=98,["3082040173_183040929"]=1,["4148568897_1458389014"]=17,["2991531424_2308625789"]=21,["2449118928_2805866304"]=29,["2631003691_2207189633"]=38,["2150742225_1381215172"]=132,["3956548677_2227883659"]=123,["3566848565_1446807450"]=66,["2248670335_1217148891"]=29,["1468498599_1572149390"]=44,["206463857_3290713921"]=48,["1836532583_644340906"]=12,["447811269_1449123153"]=19,["683217186_1496832492"]=31,["1046415114_159064821"]=40,["1775913466_1011230856"]=76,["429284280_2395433928"]=58,["3467307140_3841854073"]=127,["2629064551_3712955691"]=83,["2440902198_3234222219"]=115,["704681465_793419110"]=74,["2503832223_1455385128"]=6,["2062764768_1715938775"]=15,["3970555441_983377222"]=14,["3723997273_1416376647"]=19,["834971824_1049469433"]=18,["619555341_2753829307"]=107,["375256893_3220860768"]=49,["4159187028_2931357061"]=72,["1445147092_858559192"]=96,["1202084005_451240316"]=72,["2873202746_2425624377"]=99,["1822996143_902830513"]=70,["2155531639_3814486589"]=38,["2989010722_1583031364"]=88,["1206275195_1128530607"]=56,["2526021174_1552363197"]=141,["1135372949_288034986"]=9,["4099988748_400848748"]=60,["2319641477_829825948"]=85,["3793231902_627700083"]=23,["2705612914_2215439415"]=28,["1080889045_3612090318"]=131,["3027335381_4128848224"]=69,["320795015_1759548688"]=13,["305035850_1905118169"]=51,["29989093_1752240239"]=55,["1128643821_1876211361"]=104,["297685196_2941263615"]=76,["1973552500_2493473202"]=112,["3075985176_2552881154"]=74,["2469040346_3876042754"]=117,["1833991438_1019216566"]=56,["1139785424_847871370"]=89,["416541380_3571472417"]=53,["3193139259_3671816753"]=2,["1394549097_1366885616"]=50,["2984907375_2270624828"]=52,["1938522340_1903633615"]=33,["1870644467_1809583971"]=42,["1304106476_3486961551"]=24,["1372457208_2331595408"]=70,["276157135_4020280569"]=16,["828103203_166492844"]=82,["294905471_3336186609"]=37,["2459649576_2979617767"]=43,["3754499040_1780077306"]=90,["3072139525_1955372027"]=104,["4250665519_3726788803"]=74,["151945299_4187297521"]=9,["3484712983_2843719244"]=131,["1183571758_2427335353"]=142,["358759224_312956282"]=3,["1757277365_1884283424"]=23,["3998564817_2340888102"]=44,["992211330_3881955947"]=15,["1395020414_3025274762"]=118,["558417065_40038567"]=12,["928399271_3841349942"]=7,["3160560832_700438557"]=96,["3146004789_2834459620"]=117,["3725052926_3363508226"]=26,["1054257739_4218119812"]=118,["1175005835_139927495"]=62,["258346272_378479201"]=120,["3389496034_304287663"]=40,["1671763385_3814257456"]=47,["1850243705_1105868218"]=50,["1775076292_4011363550"]=36,["2254445366_634760981"]=91,["4155089628_3183093637"]=49,["1034014282_2306409406"]=51,["2950282901_2573271184"]=67,["681362784_3055759992"]=106,["692214869_1003580177"]=143,["1208144055_1351814685"]=94,["4071663821_310777913"]=29,["2675115186_54678336"]=99,["4089624643_1033621222"]=54,["2270282629_1527168693"]=34,["2926601992_4038590016"]=49,["759317006_3312820591"]=55,["1033480285_450072212"]=51,["2426559054_2794782939"]=77,["2015817484_488669199"]=7,["3972932762_603153972"]=105,["2198106138_2917262777"]=139,["339517728_2198127788"]=90,["74565217_2869100511"]=41,["183190868_712997620"]=20,["3881353447_399488997"]=87,["958718542_147025912"]=98,["1062117749_2272193637"]=13,["2612573951_562371020"]=91,["3976876427_1079451862"]=24,["3591513296_3280330516"]=140,["3049162126_3303118377"]=40,["268406726_1054943333"]=28,["3846388178_3445499182"]=66,["2658824702_3640582748"]=93,["3633042602_3787878661"]=89,["2993935348_3383478706"]=12,["1585626948_606946769"]=10,["1624765072_1311901586"]=58,["4093009758_1001253200"]=144,["1216026572_2060636973"]=115,["2620108417_3599021564"]=94,["4035854735_793249744"]=114,["2399195524_859011228"]=13,["2595330649_2527541796"]=14,["3693649191_1041188545"]=105,["4056821427_3071460191"]=73,["3522497785_2099809612"]=21,["2565967731_2330510460"]=114,["1468284450_3628258882"]=98,["532884045_735860232"]=9,["110033702_3835735475"]=38,["3573587226_315914027"]=112,["1109319928_1580486904"]=120,["2647592945_4195560649"]=134,["95991721_2063491055"]=145,["1707006974_1726601054"]=129,["490465271_1499714997"]=32,["324169968_4106720406"]=93,["2509064341_2942381466"]=51,["2173679549_2558372897"]=105,["1830413984_1752434310"]=130,["818581760_1069461205"]=12,["3964077131_2499946412"]=60,["657402272_2171755789"]=52,["3082656310_2609926443"]=62,["2398760837_2857871872"]=51,["4159417701_3400451206"]=124,["3028510911_3943197397"]=14,["1775503098_3362618783"]=115,["3510835134_3307553508"]=66,["107530429_4036200258"]=77,["3169368702_3745700365"]=35,["1466138304_802631997"]=15,["1835681309_2425843177"]=31,["2870357585_3042647775"]=135,["2192264654_2303586471"]=37,["163607839_3943777134"]=92,["20524619_3137067603"]=17,["2001272735_2145276802"]=114,["2620292763_744217541"]=20,["1499532465_1712654730"]=28,["1603166620_3825770498"]=86,["1423678724_3357202841"]=140,["3527521931_1988377763"]=77,["2438136124_3756771654"]=74,["3897605644_230259012"]=16,["913916493_3626846197"]=39,["1030152554_3358713903"]=118,["756357554_1245760195"]=101,["2675540883_1316828886"]=111,["17235260_176381932"]=86,["3326638044_3737248549"]=146,["3310629940_964701821"]=43,["944938165_323298231"]=111,["305863001_1393572849"]=17,["3522363818_2298818665"]=6,["1017833421_1782418276"]=17,["3359960609_3852236993"]=144,["1292811863_3259397525"]=5,["491200994_3591943871"]=44,["3800453381_1014648726"]=131,["4289962177_4275267476"]=124,["1103596304_2753542914"]=36,["3407642949_1035310911"]=32,["3498032990_3575250452"]=5,["362470405_2370910728"]=68,["2626441103_3133735697"]=87,["2715942436_1518540790"]=125,["3036428688_1242181271"]=101,["2010576684_2404865301"]=99,["1065637214_282474217"]=144,["2338724392_1279588633"]=18,["2123479537_2086148582"]=18,["2196968238_4064464837"]=39,["2481209156_2509905154"]=46,["958678575_2380145983"]=71,["283498602_3606150750"]=127,["2578890780_1998157830"]=136,["2062149546_2240548900"]=83,["3946182469_4000499915"]=76,["1374334571_2162049912"]=23,["2890014916_3808446921"]=8,["2968987261_3542949953"]=79,["4052243882_2626711220"]=36,["216847963_1389909064"]=123,["3825448048_3274857462"]=135,["4117991882_1847123855"]=98,["3346634692_1168952708"]=9,["2037902673_527198431"]=86,["3063932092_184579768"]=15,["233146950_688887312"]=139,["616797138_2173102414"]=8,["3749278665_3506782825"]=7,["3978868815_3188035263"]=134,["3122950021_3444464015"]=88,["2314530015_2576341992"]=99,["3463251708_3101984005"]=22,["4185907634_2893922774"]=16,["3416669371_2316963523"]=37,["1970125150_2323978205"]=18,["3974347732_3904353560"]=98,["2616678495_1869382657"]=11,["1435122498_1319908435"]=46,["1363325487_3891094572"]=30,["1451612535_1489157090"]=34,["175457415_4267395925"]=47,["145124433_1621751335"]=54,["2518505117_2769549242"]=79,["754231753_2155311311"]=92,["1484207352_1675958796"]=60,["3407487778_1622849341"]=107,["3089341225_2744979402"]=82,["103063503_779849985"]=60,["3494831329_2525664136"]=112,["3777957362_314112762"]=60,["888020167_430336252"]=29,["2645593138_182963977"]=60,["1969593211_123312062"]=60,["3930717995_1613908573"]=25,["1573056238_66777793"]=18,["3786147379_1277199942"]=60,["1883834961_1902336208"]=10,["3819218368_2492422030"]=81,["29304851_1931113453"]=81,["3859852440_2214166137"]=81,["2275966168_2387878113"]=1,["4008476121_1270530866"]=130,["2849442177_1409725362"]=123,["1420576536_1437208287"]=85,["2475359963_1181673107"]=81,["90859912_1127414021"]=66,["112543578_1704222421"]=43,["2904912682_1799775178"]=89,["1691607797_153393363"]=93,["784628789_2299731476"]=141,["2071267133_2848691316"]=141,["2454608873_2136586608"]=141,["1232227621_436946062"]=141,["3923335362_2599308770"]=141,["2002712443_2676602819"]=2,["4090154618_3938366584"]=64,["4005336713_4057767775"]=26,["1694529097_317003277"]=53,["433512081_2190962163"]=64,["2577168909_3446144259"]=74,["895096815_2203995068"]=146,["3783381808_2802869923"]=1,["1635677699_1484159580"]=11,["774596418_446939715"]=11,["4122471243_319777700"]=11,["487093689_1683280038"]=11,["112492875_1160309413"]=28,["2473951778_1158391034"]=11,["2874582321_2179458025"]=135,["2110975179_691536174"]=129,["1064799971_467320694"]=11,["3908083186_2459609845"]=41,["991171421_2525107106"]=36,["3895052597_4042209266"]=11,["3991664920_3420372988"]=15,["3336731680_2778802931"]=11,["1880731633_4178709826"]=34,["2431089428_2403163670"]=114,["2365182911_1732474872"]=85,["844358611_2333948967"]=55,["4055204532_2106026725"]=72,["2751789500_1566564485"]=72,["3670548646_88962760"]=61,["4081727084_91912527"]=132,["1494136184_2074060712"]=5,["849468365_852990721"]=48,["313663670_2185082724"]=6,["1407965621_863033019"]=105,["822517909_1201287679"]=63,["1908041524_2529413850"]=54,["3367526567_1362148561"]=19,["3203287423_2415116671"]=132,["123191798_306624002"]=94,["3531867381_290140920"]=83,["1818278849_403468269"]=128,["695798595_171738667"]=128,["2743642624_1876352484"]=86,["272443279_761209033"]=139,["3578013690_1725082567"]=128,["1100177793_2580135248"]=99,["1825588699_3909741102"]=84,["863903520_3822488269"]=128,["2788410784_242415235"]=139,["2652652298_3655077556"]=47,["3627626225_1091137602"]=128,["3319890744_1163511451"]=128,["921953035_415657474"]=128,["3512493952_3894764438"]=128,["984854229_2722891073"]=128,["2239432578_1424858535"]=128,["3250016815_1436966166"]=128,["3803285521_2781608136"]=128,["3183236751_3671591449"]=129,["2043537254_1628044086"]=128,["2375383694_2052183660"]=128,["3199902970_2929175784"]=117,["1886261278_4292652072"]=41,["3894714434_4189525204"]=20,["4076996796_4038059894"]=23,["4250241880_3421177255"]=88,["3507207036_1793679758"]=35,["684170405_2973331596"]=69,["1839445361_2059306519"]=41,["1446668387_2113321720"]=51,["3124576202_2773111848"]=74,["1501780223_1627953041"]=10,["3659667498_3183838105"]=96,["1677396053_1556384909"]=41,["1187823087_4283932599"]=41,["3327941573_3921639351"]=39,["1707763665_255474281"]=41,["3702691390_1087844740"]=36,["145545145_3643567124"]=95,["4191696673_414285663"]=2,["1239520236_135916130"]=28,["1069108995_3715998159"]=101,["1555007205_572353372"]=43,["1148735369_4238369005"]=136,["574161503_1278119846"]=101,["802211484_3613982397"]=43,["4222167249_148870792"]=101,["2459201359_4040007377"]=79,["2687852778_2301425982"]=93,["3883868024_2526264112"]=13,["2467185101_1036928662"]=115,["1205159039_67152274"]=46,["3749914996_4011028578"]=40,["2878496521_3994216752"]=98,["1114806437_1033908950"]=79,["946249579_2600132462"]=90,["3539309412_1941784104"]=146,["3619907841_3867253360"]=31,["2185108901_1893282144"]=79,["2124711955_460679104"]=74,["580192322_4030478348"]=79,["1585752920_3054902095"]=68,["743104915_2138016847"]=22,["1709501599_4137247780"]=79,["2445046135_3988867454"]=79,["2403389015_1204209490"]=90,["2453864194_2046419891"]=92,["571248627_3450107722"]=92,["4180711743_2834729652"]=92,["3076053683_768834100"]=66,["2783289311_3587239632"]=45,["3908178600_4266637467"]=17,["2449898003_4123173521"]=62,["754434213_1216499796"]=92,["791283199_2637141141"]=92,["37690588_3577310670"]=92,["404739808_3132577697"]=47,["1172326186_3986756776"]=58,["1964044885_1480952"]=147,["3615004527_2000134405"]=47,["1278478905_1662704768"]=93,["438085820_1852213273"]=47,["1998123265_1311004221"]=47,["1395868306_1464007522"]=135,["2857985169_1605106036"]=68,["3511243339_2601105067"]=47,["3347914520_3920333007"]=128,["705133469_1810079175"]=5,["3745384747_3715605222"]=63,["3032047928_2338030487"]=36,["3346092496_1143982549"]=3,["2929767860_3134938719"]=34,["1308617254_2815769883"]=148,["1798871652_1995500958"]=47,["3050714873_304922845"]=47,["4125416197_3188573351"]=33,["4142449900_550717718"]=101,["3522803316_31455247"]=20,["654879078_1990885108"]=47,["1859481616_3660914459"]=121,["3545248910_1844597678"]=47,["1979170348_3296565653"]=5,["2614508322_3405314587"]=7,["3233036191_2394514236"]=73,["784127284_928770073"]=110,["1463094049_1014714665"]=149,["1943064277_725688784"]=73,["2981246598_456338391"]=111,["208917809_2892760379"]=73,["2534915915_2133002676"]=73,["2979695885_3880845072"]=8,["1595631927_1972344073"]=82,["2353742044_1850141812"]=12,["3628248586_1039577515"]=73,["3509552105_184867648"]=123,["26948349_2672853759"]=8,["3006039220_1425586249"]=5,["3549152206_3585642711"]=73,["1701483944_3425584807"]=117,["831156725_2301176783"]=32,["724582655_1188666472"]=6,["3394183571_3788997389"]=80,["3819471505_2359408364"]=18,["4175008197_2529935893"]=140,["1771541017_3779789203"]=150,["364544679_4163258960"]=15,["344067591_4246360166"]=124,["2707210853_455058253"]=18,["3192802877_2259905241"]=10,["3474747761_1736199400"]=18,["1929993211_1454698432"]=18,["976259642_1166815137"]=60,["1742022016_2949497458"]=18,["1953722585_1466163277"]=18,["497230311_1247828008"]=18,["2779623229_420144152"]=18,["3752385590_1105312257"]=136,["2360198844_3140603041"]=18,["1242411345_2027554562"]=127,["1980313626_1363237887"]=144,["834028348_3286648148"]=127,["997571967_395934034"]=12,["2194848374_1713244088"]=127,["513680002_2198860613"]=45,["3883883771_2431085547"]=54,["3450278551_3511240909"]=5,["3301746268_1357301183"]=127,["765992553_3804234299"]=40,["902983120_1969384804"]=127,["688221199_337446893"]=127,["1394326557_3080307825"]=72,["1240410692_945323767"]=51,["3496538441_108493641"]=61,["4023105138_3115508976"]=123,["4126959010_1347107270"]=146,["3177566193_2548455996"]=58,["310608933_585478630"]=107,["567614356_3596386855"]=146,["44770079_3218538267"]=12,["1219195103_4037079911"]=7,["3055990860_1154356155"]=77,["511776032_3095686514"]=82,["4195385794_2940087830"]=55,["208454201_291417516"]=86,["2541321506_2742110412"]=33,["3458372283_314715297"]=146,["3985523577_2580496553"]=64,["1192071924_1597924349"]=93,["206044011_2524364094"]=91,["718340007_2443486101"]=146,["3155543144_2541748900"]=140,["2206587602_590303517"]=140,["1027953749_1849182706"]=136,["2622646778_4240795852"]=115,["3100872002_3859715615"]=26,["3672393948_738444611"]=110,["766131353_756816165"]=136,["2022681872_680565574"]=30,["3144615766_725137428"]=136,["3851725408_1808454540"]=100,["1381260162_4255814928"]=136,["132456586_3715243888"]=136,["3989557579_1807592954"]=61,["955523926_793321017"]=29,["2219611976_3256229722"]=2,["3236670527_418301865"]=120,["1298662782_4114321469"]=130,["342182641_442350060"]=141,["4052570883_642695253"]=151,["4067058913_1614112986"]=100,["4204733846_3683695232"]=2,["4081111820_3439711260"]=31,["454254678_2485837978"]=2,["1319246686_3035785978"]=2,["4231533082_824084935"]=111,["2992768118_2944081152"]=86,["1326181128_2134160797"]=96,["3363523347_2184579199"]=50,["440754158_2258641266"]=63,["2643594770_1448355706"]=50,["4086315888_1798725871"]=2,["2602402796_1197661660"]=47,["2852313722_3639720284"]=2,["1156006670_1012694253"]=40,["3223374257_4224066170"]=62,["3256769947_1007292653"]=39,["2577388192_448236517"]=75,["1145638838_3527430217"]=1,["1476210037_3089989596"]=51,["1114797353_2520595202"]=132,["1620921957_3814773613"]=72,["3646788113_149910622"]=32,["1471783461_475744443"]=132,["3891778260_2819021890"]=132,["2579122226_3341839852"]=61,["1133794451_3922481680"]=82,["1080356597_1795040552"]=132,["1735590322_4025286672"]=53,["794325996_93949118"]=128,["1360642128_1265463289"]=132,["1265187356_3917155625"]=106,["174269263_2941549834"]=133,["4002971333_3377816261"]=31,["2900058552_3714856974"]=132,["2136657366_4209232486"]=87,["3231077370_1472972622"]=87,["2275228523_1056516467"]=80,["3060067276_1219671554"]=5,["2190835262_2265430647"]=87,["3707443522_1169413067"]=85,["2400743078_3679524800"]=8,["3055249648_3148196658"]=90,["3400331039_3198923704"]=71,["225912374_3749957422"]=106,["3001662447_924269957"]=87,["1201802073_3756797853"]=87,["3213322138_1039518240"]=87,["1372849249_4199667053"]=82,["3600930106_1826259993"]=132,["2052716653_4024115751"]=68,["4091159650_1569834729"]=82,["461363196_3515138236"]=82,["1279738864_588983404"]=60,["2812207596_264821661"]=82,["1154575533_1104935407"]=82,["2136331105_1644932701"]=77,["396209659_3866165674"]=82,["3567487838_483077882"]=105,["1433122155_1528714632"]=129,["1061428397_653113957"]=32,["3857108260_3020436389"]=145,["1301892871_3947510363"]=129,["328359903_1432088203"]=129,["4243413684_2697321545"]=16,["3944208132_790405151"]=129,["1532602357_2604741862"]=129,["4212168319_3527364752"]=107,["2226359707_1427272827"]=107,["184170416_3448645494"]=107,["2773368993_3322976140"]=130,["1598770360_3981880598"]=107,["2992338785_1246764666"]=152,["2989003202_2717956234"]=107,["3665983551_624921949"]=60,["523459860_3870100700"]=125,["3143884387_3579058356"]=26,["4204114455_3594124284"]=3,["2944216549_1391499301"]=125,["4196139009_966769903"]=62,["4117855940_2409357712"]=108,["4216999399_3996673556"]=125,["56017672_3183639795"]=41,["458468544_3082350341"]=144,["3051897716_223685463"]=144,["2670881998_2278782715"]=144,["3482069762_392528116"]=95,["2013961936_1371663416"]=144,["3590088536_2080256435"]=55,["1601266952_165396704"]=84,["3474047575_472934074"]=95,["2387056591_3950476176"]=146,["506839131_1642109892"]=81,["3812999454_933476621"]=73,["3723474260_1138834998"]=5,["4147063749_1487396654"]=98,["2742259396_2278004145"]=123,["3961954181_3306302894"]=123,["1182750596_1031780771"]=14,["1221921740_3694337114"]=123,["2102935351_761442152"]=86,["3667309897_2345531798"]=26,["1738440059_2920834307"]=84,["458244417_2088073053"]=128,["3690650674_2414304652"]=88,["3501828515_1413142469"]=106,["1275927401_57268217"]=61,["3637726404_2553878593"]=123,["1071210868_1829435759"]=111,["122113109_931069267"]=153,["1310095115_2652748144"]=125,["2981066475_2973045522"]=90,["2182141101_2283939087"]=132,["1087840031_3315695141"]=127,["2562684592_3141598468"]=114,["4180282472_2890749787"]=54,["4010613364_3291756277"]=25,["1465736246_1739041083"]=114,["1624204788_38132300"]=21,["2149478214_4079468061"]=111,["100718895_3112419357"]=59,["1109504973_4284290497"]=38,["304217470_2622184601"]=21,["2841314300_3988261550"]=114,["2321406402_500543344"]=114,["1550439632_3096384137"]=71,["1241572103_2590322391"]=25,["3979241461_466236605"]=45,["1069116878_1377058062"]=112,["1046511901_3861246396"]=25,["3140635916_2699377893"]=13,["1125062325_2598710649"]=25,["3041000884_3557826863"]=35,["3645375399_4272777241"]=25,["4199471513_247516615"]=25,["1000364641_761274615"]=69,["905345788_2946069160"]=69,["3945197515_3979149348"]=69,["3467971788_2327564314"]=88,["1181171913_1639500086"]=69,["154292616_594374953"]=69,["3681011734_1858485668"]=69,["709024495_1392463456"]=33,["3655137462_2676580787"]=86,["572682902_3797946734"]=130,["4111456717_3371803670"]=21,["3814587453_3348379728"]=112,["2194757159_2863245197"]=35,["3140487766_4113070603"]=36,["1428496120_699847973"]=77,["1344725091_158468278"]=3,["3598867753_968967418"]=12,["408951392_2125392182"]=103,["3240221053_3150875450"]=77,["432940448_1915955389"]=70,["1112083236_110816498"]=37,["211927282_2739719949"]=124,["1235296344_3639133997"]=36,["2562481263_1963395863"]=34,["1429548765_3979355114"]=43,["3026852069_430876830"]=138,["954083771_1087364783"]=105,["956609982_1507290759"]=27,["785817419_1523563348"]=68,["3721559118_3643103491"]=76,["2576509914_1237415022"]=24,["2814342636_1767439565"]=22,["3801378345_2239646113"]=19,["285200787_3010812501"]=16,["284612_3580806650"]=115,["2366317732_3664108811"]=136,["3860239931_2934728243"]=46,["2829598037_1331400788"]=99,["3968556473_1622932167"]=36,["3550363213_2661619878"]=88,["2696785850_3155576575"]=38,["1475452149_3918452354"]=23,["4273297221_3756421131"]=23,["1900672880_3143484611"]=139,["3153639719_928900713"]=144,["1211956023_1007969242"]=7,["602720591_3798725005"]=33,["315203836_4228923767"]=83,["877776391_3216257327"]=77,["2314926237_198135497"]=4,["686959774_3243941870"]=34,["2913902687_1292561709"]=76,["2978046944_576229086"]=40,["3507801193_1537264773"]=89,["1650065155_3935275583"]=34,["1113861170_1000601507"]=76,["1340480131_443656152"]=47,["946793377_1179491500"]=96,["279411681_79668620"]=100,["1532195559_2499708000"]=40,["3747879831_3737937436"]=36,["850227188_1965534205"]=62,["1339111265_1318673439"]=43,["2303432798_2990836414"]=68,["3611732854_1193616930"]=81,["3296285858_859904340"]=36,["4228528192_3679378913"]=80,["792343880_1542664609"]=10,["431187184_3498480294"]=15,["4113325363_2949270710"]=15,["2650176742_523775923"]=68,["3767632911_3524365543"]=120,["2255065465_1016823834"]=45,["4247156111_1097204932"]=130,["4051291445_3544064538"]=10,["2784916707_119933714"]=31,["185374467_2759574869"]=91,["3232205192_54835491"]=49,["3099755022_4175822767"]=154,["1910477918_3923159924"]=4,["1617645703_1158480634"]=8,["1513439615_2973881906"]=20,["3731243133_3679748713"]=1,["3282398547_2951246036"]=29,["3321264477_1365662291"]=135,["2974322125_3202272021"]=86,["1246688546_162862519"]=54,["2125681089_2246314756"]=52,["3339306365_191188846"]=86,["2581734611_1920821135"]=7,["3789190978_1233025979"]=95,["3020964153_986766178"]=56,["920245209_2566669448"]=106,["4233451261_2278648504"]=117,["3046829892_3862000861"]=35,["2972567099_884931342"]=65,["2524104254_404311524"]=106,["3887119540_4109291591"]=1,["1984219235_106112807"]=7,["2769956807_4239739254"]=154,["1029160460_2556244903"]=120,["2741868233_656637043"]=133,["1810154583_2661671392"]=12,["2651771528_3483493447"]=89,["3716586680_3424841136"]=100,["3869488016_2330887416"]=38,["3739816813_1813866703"]=36,["1239438875_658630346"]=43,["3717580394_3461229574"]=46,["375104569_961159095"]=5,["1100199038_3566309872"]=21,["1230444601_3764244273"]=51,["2430790191_2034955132"]=92,["4207699456_3079142854"]=91,["3686452177_3671456913"]=83,["3733701284_2101160107"]=71,["1765356283_2745752648"]=78,["1860498650_4286992453"]=8,["2581526084_2782719023"]=20,["4083053439_2600481031"]=46,["268384903_4250563792"]=16,["5216624_2673735872"]=14,["1559110500_2296318853"]=10,["2236580305_3687249419"]=35,["870645014_613092757"]=24,["3133627200_1681981815"]=31,["623003121_3725997279"]=60,["1593660117_1616287814"]=3,["1946987315_3426601798"]=115,["3700683218_4153798726"]=126,["3256316474_2790565458"]=63,["3505052705_3870919510"]=42,["78166872_1807082905"]=132,["1192713741_906208422"]=75,["3315019514_692561182"]=55,["663702842_186986478"]=62,["294069211_1249582469"]=55,["2066662103_3455721165"]=15,["969524470_733450237"]=1,["2714817295_3449599031"]=14,["4252540444_970342753"]=123,["1292006006_1792723408"]=81,["1247241678_2066751897"]=124,["3272516175_4289623148"]=155,["1145819791_4250901954"]=98,["1313793463_3455178155"]=10,["1884498340_3113468407"]=3,["3663598249_426568492"]=95,["147030677_1790100861"]=1,["559415538_160193137"]=112,["35358596_797761745"]=9,["1985265600_3560254934"]=120,["1936149339_3682643453"]=136,["234674560_1331613222"]=151,["700613239_1208453265"]=22,["3952850853_813988690"]=9,["105141203_200330316"]=68,["34962688_454054042"]=45,["2193840233_3490684238"]=112,["96079845_3432461574"]=30,["1338499364_3481543285"]=105,["435507077_2964539239"]=68,["86048718_1107257058"]=124,["3742101464_4243024544"]=91,["3612368963_2958413839"]=93,["2332031365_3424849698"]=56,["3757723841_698711088"]=100,["2626732660_522060667"]=113,["1504679526_3338893623"]=74,["1769754667_2354148215"]=70,["2292380561_214411225"]=156,["88959406_2808565714"]=90,["2437584544_2956991119"]=19,["1582725445_3198987962"]=45,["1409963297_3412145334"]=68,["4204112642_2974569464"]=110,["1185736125_2575187632"]=40,["4206081191_147145780"]=1,["896867128_1415075345"]=9,["338282614_2311373381"]=14,["3971416567_2645889491"]=21,["155640253_2069121957"]=89,["2460131608_381258072"]=74,["4243181012_1865859293"]=112,["2813543517_673774561"]=105,["609295304_3794473948"]=72,["2603047195_1887707705"]=42,["2768315969_3101790725"]=29,["3801375238_3024500972"]=19,["4277234279_2751567001"]=74,["3822994154_1541534283"]=41,["373240587_4221259684"]=74,["2130741743_2845212881"]=14,["4099436182_3369113651"]=79,["1676363499_1844596080"]=10,["527826371_3111418117"]=10,["3111680121_2023189250"]=28,["144136935_2595400514"]=60,["1234686399_3350029711"]=33,["3938893674_2555895327"]=118,["2096787065_396331651"]=156,["3212911541_3842901902"]=19,["2209113481_3971285735"]=101,["809350479_1410782885"]=45,["2106541127_905590340"]=36,["4167153419_513194283"]=45,["1776485553_668017003"]=25,["2862797872_4105250914"]=57,["4078294773_1889603600"]=42,["1971121223_4135288733"]=2,["1548780009_3252517951"]=17,["1004209810_975440342"]=15,["993775059_313532147"]=88,["473367599_1793184950"]=76,["1606145329_2258702431"]=71,["4121470780_3366298875"]=105,["888824889_2010282215"]=33,["286663424_2076147419"]=40,["2567495910_664285164"]=56,["6143341_1241027637"]=79,["3269895394_3643216959"]=63,["4051618851_934130590"]=33,["786765878_831538727"]=91,["2593661039_1277455237"]=119,["4041928164_126964399"]=8,["3263629582_1467859837"]=1,["799003729_2007385531"]=81,["2256829486_691449198"]=20,["1085654949_4032981797"]=51,["976791583_3360731074"]=18,["790097662_2344662234"]=120,["2663769224_1758085602"]=51,["1126258943_1877938400"]=30,["3629946841_508937162"]=125,["2107264323_2994002970"]=98,["2057482861_2970584922"]=51,["1718749527_3427247515"]=86,["4063276119_285069002"]=85,["2330578696_3524937484"]=33,["58663204_203522985"]=125,["4029838829_1870585834"]=7,["200279980_1807075310"]=58,["1666382354_3187943258"]=129,["142628158_1188368781"]=46,["497917996_2628185080"]=84,["2706739825_1886176380"]=2,["657862284_3189514271"]=80,["1064495700_624112200"]=63,["300638621_3334934865"]=50,["1668325625_2593706638"]=24,["1974995372_3845901994"]=135,["564499991_4286630692"]=24,["528115641_572563871"]=24,["2759753099_304752108"]=66,["1653262914_1133536195"]=7,["1198156025_1155331491"]=8,["2309822188_1163979220"]=28,["3710385765_2139270416"]=9,["1745963374_1722390512"]=40,["2571205448_1932274652"]=130,["756423767_1024321593"]=76,["298549229_3102408246"]=40,["3432989348_3182545121"]=72,["429083811_1894088864"]=61,["2333482627_1343031008"]=61,["1377800422_2690849799"]=42,["2144763308_3155629629"]=48,["4127377066_1949166049"]=68,["2340709024_4259072072"]=100,["2182288981_4225827097"]=51,["1705872416_1360339124"]=87,["185587584_3456778399"]=16,["2555780374_627764588"]=99,["3586718666_2626292946"]=54,["1134686984_3319361768"]=31,["978157378_554420112"]=150,["1242308220_4055673149"]=114,["3075762101_1341757156"]=37,["3767937812_2606990382"]=17,["627514062_32080881"]=118,["4036197894_1965933647"]=5,["1551671855_3474841683"]=53,["1055094146_1513138379"]=54,["2819080798_1506370936"]=95,["56863612_3079544634"]=40,["937510885_4238402827"]=53,["2356425994_1350270048"]=19,["2641848704_2024629699"]=112,["3631386114_3219378619"]=15,["4042265990_3126147174"]=134,["24409299_1914976164"]=8,["3253743854_979365912"]=157,["2716751640_178336094"]=123,["2259640661_976975607"]=2,["2647321679_3358515630"]=16,["1029673597_756738901"]=50,["2841363830_4015578124"]=14,["1061994160_3150427485"]=34,["2426159363_255428349"]=12,["467860929_3473212012"]=41,["864937582_1733056526"]=45,["3353871370_709742718"]=33,["3955174653_3392271949"]=64,["432718478_1929341475"]=106,["4161817567_3692150314"]=9,["3945619499_2720814175"]=10,["1609710726_339535447"]=74,["618738763_1331886751"]=4,["338740368_2566560481"]=62,["626746928_2050301246"]=71,["1129976461_545125128"]=10,["2524602273_1816935846"]=35,["3322320010_2255226593"]=15,["3372051865_3431045374"]=1,["1677007655_3533895311"]=114,["3571370753_3127072286"]=84,["1621277435_3360022949"]=158,["91761008_177406523"]=47,["2051461298_2856899546"]=84,["2636086311_569313322"]=37,["1799820382_2958985144"]=131,["19672284_306855527"]=42,["4151855764_997983649"]=6,["3332323115_791848406"]=18,["3397653860_1295949680"]=29,["289373728_563817213"]=43,["942729837_2329297587"]=115,["3017212543_545373651"]=6,["3354832777_1391941578"]=61,["4110532373_2660020964"]=38,["1107997820_2216884734"]=29,["199357964_2435710748"]=137,["3389879283_3927382154"]=62,["1727483426_1767538395"]=7,["3669853662_717777789"]=91,["2632282461_1796722554"]=23,["2401281125_3995434963"]=70,["1529265363_456117037"]=70,["1242876155_2993942206"]=70,["3885892611_3302000140"]=156,["3860550743_514830847"]=26,["1167396673_1809248927"]=159}
}

local function tagSet(tags)
	local set = {}
	for t in string.gmatch(tags, "[^,]+") do
		set[t] = true
	end
	return set
end

-- picks a legal book move for the current position (and whether it is a gambit), or nil.
-- Third result: the best legal named gambit available here ({uci, name}), whether or not it is chosen.
local function pickBookMove(rootMoves, styleNameIn, alienAlways)
	local entry = BOOK[h1 .. "_" .. h2]
	if not entry then
		return nil
	end
	local legal = {}
	for _, m in ipairs(rootMoves) do
		legal[moveToUci(m)] = m
	end
	local st = STYLE_PARAMS[styleNameIn] or STYLE_PARAMS.Normal
	local bestMove, bestScore, bestGambit, bestUci, bestAlien = nil, -100, false, nil, false
	local opportunity, oppWeight = nil, -1
	for _, e in ipairs(entry) do
		local m = legal[e[1]]
		if m then
			local tags = tagSet(e[3])
			local sc = e[2] * 2
			if tags[st.arch] then sc = sc + 3 end
			if tags[styleNameIn] then sc = sc + 5 end
			if styleNameIn == "Alien" and tags.Alien then sc = sc + 8 end
			if tags.Alien and alienAlways then
				sc = sc + 14 -- the Alien / Martian gambits are playable whatever the style
			end
			if tags.G then
				if st.gambit < 60 then sc = sc - 5 elseif st.gambit >= 120 then sc = sc + 2 end
				if e[4] and e[4] ~= "" and e[2] > oppWeight then
					opportunity, oppWeight = { uci = e[1], name = e[4] }, e[2]
				end
			end
			if sc > bestScore then
				bestMove, bestScore, bestGambit, bestUci, bestAlien = m, sc, tags.G == true, e[1], tags.Alien == true
			end
		end
	end
	return bestMove, bestGambit, opportunity, bestUci, bestAlien
end

function Claude1.openingName(fen)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	local id = BOOKNAMES.at[h1 .. "_" .. h2]
	return id and BOOKNAMES.list[id] or nil
end

------------------------------------------------------------------------------------------------
-- root search: iterative deepening, aspiration windows, easy-move detection, 2-phase MultiPV
------------------------------------------------------------------------------------------------
local rootInCheck = false

local function legalRootMoves()
	local pseudo = {}
	local n = generate(pseudo, false)
	local chk = inCheck()
	local out = {}
	for i = 1, n do
		local m = pseudo[i]
		if makeMove(m, chk) then
			unmakeMove(m)
			out[#out + 1] = m
		end
	end
	return out
end

local function rootBonus(m)
	-- small style-dependent tie-break in centipawns, only used to rank near-equal root moves
	local from = m % 128
	local rest = m // 128
	local to = rest % 128
	local flag = (rest // 128) // 8
	local bonus = 0
	local p = board[from]
	local t = PTYPE[p]
	local capture = board[to] ~= 0 or flag == 2
	if capture then bonus = bonus + style.rootCapture end
	if flag >= 3 then bonus = bonus + style.rootCastle end
	if (not capture) and t ~= 1 and flag < 3 then bonus = bonus + style.rootQuiet end
	if style.rootCheck ~= 0 then
		if makeMove(m, rootInCheck) then
			if inCheck() then bonus = bonus + style.rootCheck end
			unmakeMove(m)
		end
	end
	return bonus
end

local function copyPV(m)
	local pv = { m }
	local src = PV[1]
	for j = 1, PVLEN[1] do
		pv[j + 1] = src[j]
	end
	return pv
end

local function enterRootMove(m)
	makeMove(m, rootInCheck)
	MOVEAT[0] = m
	PIECEAT[0] = board[(m // 128) % 128]
end

-- single-line search of the given entries inside (alpha, beta); nil when aborted
local function rootWindow(entries, depth, alpha, beta)
	local bestEntry, bestScore, bestPV = nil, -INF, nil
	local a = alpha
	for idx = 1, #entries do
		local e = entries[idx]
		local m = e.move
		enterRootMove(m)
		local score
		if idx == 1 then
			score = -search(depth - 1, -beta, -a, 1, true, true, nil)
		else
			score = -search(depth - 1, -a - 1, -a, 1, false, true, nil)
			if score > a and score < beta and not stopFlag then
				score = -search(depth - 1, -beta, -a, 1, true, true, nil)
			end
		end
		unmakeMove(m)
		if stopFlag then
			return nil
		end
		e.score = score
		if score > bestScore then
			bestScore, bestEntry = score, e
			bestPV = copyPV(m)
			if score > a then a = score end
			if score >= beta then
				break
			end
		end
	end
	return bestEntry, bestScore, bestPV
end

-- exact top-K search of the given entries (MultiPV); nil when aborted
local function rootMulti(entries, depth, K)
	local top = {}
	local alphaK = -INF
	for idx = 1, #entries do
		local e = entries[idx]
		local m = e.move
		enterRootMove(m)
		local score
		if #top < K then
			score = -search(depth - 1, -INF, INF, 1, true, true, nil)
		else
			score = -search(depth - 1, -alphaK - 1, -alphaK, 1, false, true, nil)
			if score > alphaK and not stopFlag then
				score = -search(depth - 1, -INF, -alphaK, 1, true, true, nil)
			end
		end
		unmakeMove(m)
		if stopFlag then
			return nil
		end
		e.score = score
		if #top < K or score > alphaK then
			local entry = { move = m, score = score, pv = copyPV(m) }
			local pos = #top + 1
			for j = 1, #top do
				if score > top[j].score then
					pos = j
					break
				end
			end
			table.insert(top, pos, entry)
			if #top > K then
				table.remove(top)
			end
			if #top == K then
				alphaK = top[K].score
			end
		end
	end
	return top
end

-- stable insertion sort, highest score first
local function sortEntries(entries)
	for i = 2, #entries do
		local e = entries[i]
		local j = i - 1
		while j >= 1 and entries[j].score < e.score do
			entries[j + 1] = entries[j]
			j = j - 1
		end
		entries[j + 1] = e
	end
end

-- the last three iteration scores agree (tolerance grows with the size of the advantage)
local function scoreSteady(hist)
	local n = #hist
	if n < 3 then
		return false
	end
	local lo, hi = hist[n], hist[n]
	for i = n - 2, n do
		if hist[i] < lo then lo = hist[i] end
		if hist[i] > hi then hi = hist[i] end
	end
	local tolerance = 35
	local big = abs(hist[n]) * 0.12
	if big > tolerance then tolerance = big end
	return hi - lo <= tolerance
end

-- "easy move": every alternative is clearly worse even in a reduced-depth search
local function isEasyMove(entries, best, depth, margin, reduce)
	if abs(best.score) > MATE_BOUND then
		return false
	end
	local target = best.score - margin
	local rd = depth - reduce
	if rd < 1 then rd = 1 end
	for idx = 1, #entries do
		local e = entries[idx]
		if e.move ~= best.move then
			enterRootMove(e.move)
			local sc = -search(rd - 1, -(target + 1), -target, 1, false, true, nil)
			unmakeMove(e.move)
			if stopFlag or sc > target then
				return false
			end
		end
	end
	return true
end

local function searchCore(opts)
	local result = { lines = {}, depth = 0, nodes = 0, elapsed = 0, nps = 0, timedOut = false, cancelled = false }
	if not setFen(opts.fen) then
		result.badFen = true
		return result
	end
	local hardLimit = opts.timeLimit or 1.5
	local softLimit = opts.softLimit or hardLimit * 0.45
	local maxDepth = math.min(opts.maxDepth or 64, 64)
	local K = opts.multiPV or 3
	local minDepth = opts.minDepth or 1
	local easyMinDepth = opts.easyMinDepth or 6
	local easyMargin = opts.easyMargin or 160
	local easyReduce = opts.easyReduce or 2
	FEAT.qchecks = opts.qchecks ~= false
	FEAT.singular = opts.singular ~= false
	styleName = opts.style or "Normal"
	style = STYLE_PARAMS[styleName] or STYLE_PARAMS.Normal
	yieldFn = opts.yield
	cancelFn = opts.cancel
	yieldEvery = opts.yieldEvery or 0.014
	yieldMin = opts.yieldMin or 0.010
	yieldMax = opts.yieldMax or 0.028
	rootSide = side

	rootInCheck = inCheck()
	result.inCheck = rootInCheck
	local rootMoves = legalRootMoves()
	if opts.onlyMoves then
		local keep = {}
		for _, m in ipairs(rootMoves) do
			if opts.onlyMoves[moveToUci(m)] then keep[#keep + 1] = m end
		end
		if #keep > 0 then rootMoves = keep end
	end
	if #rootMoves == 0 then
		result.noMoves = true
		return result
	end
	if K > #rootMoves then K = #rootMoves end

	-- opening book: still search briefly so the UI gets scores / lines, but do not spend real time
	local bookMove, bookGambit, bookUci, bookAlien = nil, false, nil, false
	do
		local id = BOOKNAMES.at[h1 .. "_" .. h2]
		if id then
			result.opening = BOOKNAMES.list[id]
		end
	end
	if opts.useBook ~= false then
		local opportunity
		bookMove, bookGambit, opportunity, bookUci, bookAlien = pickBookMove(rootMoves, styleName, opts.alienGambits ~= false)
		result.gambit = opportunity -- {uci, name}: a named gambit is available in this position
		if bookMove then
			hardLimit = math.min(hardLimit, 0.25)
			softLimit = math.min(softLimit, 0.04)
			maxDepth = math.min(maxDepth, 5)
			minDepth = math.min(minDepth, 3)
			easyMinDepth = 0
		end
	end

	-- contempt: style decides how a draw is valued; Normal adapts to the static balance
	do
		local st = evaluate(-INF, INF)
		drawBase = style.draw
		-- a draw is a bad result when clearly ahead and a good one when clearly behind: scale with the
		-- advantage so the engine does not settle for repetition lines while it is winning
		local scaled = 0
		if st > 80 then
			scaled = -math.min(170, (st - 80) * 0.45)
		elseif st < -80 then
			scaled = math.min(170, (-st - 80) * 0.45)
		end
		if styleName == "Normal" then
			drawBase = scaled
		else
			drawBase = style.draw + scaled
		end
	end

	evGen = evGen + 1
	ttGeneration = ttGeneration + 1
	nodes = 0
	stopFlag = false
	selDepth = 0
	searchStart = clock()
	deadline = searchStart + hardLimit
	nextYield = searchStart + yieldEvery
	for i = 0, MAXPLY + 2 do
		KILLER1[i], KILLER2[i] = 0, 0
	end
	for i = 0, 32767 do
		HISTORY[i] = HISTORY[i] // 4
	end

	local ordered = {}
	for i, m in ipairs(rootMoves) do
		ordered[i] = { move = m, score = -INF, order = 0 }
	end
	do
		local idx = h1 % TT_SIZE + 1
		local ttm = (ttKey[idx] == h2) and ttMove[idx] or 0
		for _, e in ipairs(ordered) do
			local m = e.move
			local to = (m // 128) % 128
			local sc = 0
			if m == ttm then
				sc = 100000
			elseif board[to] ~= 0 then
				sc = 1000 + PTYPE[board[to]] * 10 - PTYPE[board[m % 128]]
			end
			e.order = sc
			e.score = sc - 1000000
		end
		sortEntries(ordered)
	end

	-- ---------------------------------------------------------------- phase 1: the best move
	local best = nil
	local prevScore = nil
	local stable = 0
	local lastBestMove = 0
	local prevIterTime = nil
	local finalDepth = 0
	local easy = false
	local scoreHist = {}

	for depth = 1, maxDepth do
		local iterStart = clock()
		local entry, score, pv

		if depth >= 5 and prevScore and abs(prevScore) < MATE_BOUND then
			local delta = T.ASP
			local alpha, beta = prevScore - delta, prevScore + delta
			while true do
				entry, score, pv = rootWindow(ordered, depth, alpha, beta)
				if not entry then
					break
				end
				if score <= alpha or score >= beta then
					-- fail low / high: widen and search the failing move first
					for j = 1, #ordered do
						if ordered[j] == entry then
							table.remove(ordered, j)
							table.insert(ordered, 1, entry)
							break
						end
					end
					if score <= alpha then
						alpha = score - delta
					else
						beta = score + delta
					end
					delta = delta * 2
					if delta > 300 then
						alpha, beta = -INF, INF
					end
				else
					break
				end
			end
		else
			entry, score, pv = rootWindow(ordered, depth, -INF, INF)
		end

		if not entry then
			break -- aborted: keep the last completed iteration
		end

		sortEntries(ordered)
		-- the searched-best entry must lead the list even if bounds tie
		for j = 1, #ordered do
			if ordered[j] == entry then
				if j ~= 1 then
					table.remove(ordered, j)
					table.insert(ordered, 1, entry)
				end
				break
			end
		end

		best = { move = entry.move, score = score, pv = pv }
		scoreHist[#scoreHist + 1] = score
		finalDepth = depth
		result.depth = depth
		local iterTime = clock() - iterStart

		local changed = depth > 1 and best.move ~= lastBestMove
		if best.move == lastBestMove then
			stable = stable + 1
		else
			stable = 0
		end
		lastBestMove = best.move
		local scoreDrop = prevScore and (prevScore - score) or 0
		prevScore = score

		if opts.onProgress then
			local uci = {}
			for k2, mv in ipairs(pv) do uci[k2] = moveToUci(mv) end
			opts.onProgress({
				lines = { { uci = moveToUci(best.move), score = score, depth = depth, pv = uci } },
				depth = depth, nodes = nodes, elapsed = clock() - searchStart,
			})
		end

		-- ------------------------------------------------ when to stop
		if abs(score) > MATE_BOUND and depth >= 2 and (MATE - abs(score)) < depth then
			result.stop = 'mate'
			break -- forced mate proven
		end
		if #rootMoves == 1 and depth >= 2 then
			result.stop = 'forced'
			break -- only one legal move
		end
		local elapsed = clock() - searchStart
		if depth >= minDepth then
			local soft = softLimit
			if stable >= 5 then
				soft = soft * 0.55
			elseif stable >= 3 then
				soft = soft * 0.75
			end
			if scoreDrop >= 30 then soft = math.min(soft * 1.6, hardLimit * 0.8) end
			if changed then soft = math.min(soft * 1.25, hardLimit * 0.8) end
			if elapsed >= soft then
				result.stop = 'soft'
				break
			end
			-- do not start an iteration that cannot finish (its work would be thrown away)
			local ratio = 2.2
			if prevIterTime and prevIterTime > 0.004 then
				ratio = iterTime / prevIterTime
				if ratio < 1.5 then ratio = 1.5 elseif ratio > 3.2 then ratio = 3.2 end
			end
			if elapsed + iterTime * ratio > soft * 1.35 then
				result.stop = 'predict'
				break
			end
			-- easy move: same best move for 2+ iterations, steady score, every alternative clearly worse
			if easyMinDepth > 0 and stable >= 2 and depth >= easyMinDepth and #rootMoves > 1 and scoreSteady(scoreHist) then
				if isEasyMove(ordered, best, depth, easyMargin, easyReduce) then
					easy = true
					result.stop = 'easy'
					break
				end
				if stopFlag then
					break
				end
			end
		end
		prevIterTime = iterTime
		if clock() >= deadline then
			break
		end
	end

	-- ---------------------------------------------------------------- phase 2: alternatives
	local lines = {}
	local cancelledNow = cancelFn ~= nil and cancelFn() == true
	if best then
		lines[1] = best
		if K > 1 and #ordered > 1 and not cancelledNow then
			local others = {}
			for _, e in ipairs(ordered) do
				if e.move ~= best.move then
					others[#others + 1] = e
				end
			end
			local K2 = math.min(K - 1, #others)
			local now = clock()
			local used = now - searchStart
			local budget = math.min(hardLimit * 0.5, math.max(0.04, used * 0.55))
			local deadline2 = now + budget
			if deadline2 > searchStart + hardLimit + 0.05 then
				deadline2 = searchStart + hardLimit + 0.05
			end
			stopFlag = false
			deadline = deadline2
			local top2 = nil
			local maxD2 = math.max(2, finalDepth - 1)
			for d = 2, maxD2 do
				local t = rootMulti(others, d, K2)
				if not t then
					break
				end
				top2 = t
				sortEntries(others)
				if clock() >= deadline2 then
					break
				end
			end
			if top2 then
				for _, e in ipairs(top2) do
					if e.score > best.score and abs(best.score) < MATE_BOUND then
						e.score = best.score - 1
					end
					lines[#lines + 1] = e
				end
			end
			-- not enough lines (time ran out): fill with the best-known remaining root moves
			if #lines < K then
				local have = {}
				for _, e in ipairs(lines) do have[e.move] = true end
				sortEntries(others)
				for _, e in ipairs(others) do
					if #lines >= K then break end
					if not have[e.move] then
						local sc = e.score
						if sc <= -INF + 1000 or sc < best.score - 2000 then sc = best.score - 150 end
						if sc > best.score then sc = best.score - 1 end
						lines[#lines + 1] = { move = e.move, score = sc, pv = { e.move } }
					end
				end
			end
		end
	end

	-- style tie-break: lines within a few centipawns of the best get a small style bonus, then re-rank
	if #lines > 1 and styleName ~= "Normal" then
		local margin = 12
		local topScore = lines[1].score
		for _, entry in ipairs(lines) do
			if entry.score >= topScore - margin and abs(entry.score) < MATE_BOUND then
				entry.score = entry.score + rootBonus(entry.move)
			end
		end
		sortEntries(lines)
	end

	local bookRejected = false
	if bookMove and #lines > 0 then
		local topScore = lines[1].score
		local at = nil
		for j, entry in ipairs(lines) do
			if entry.move == bookMove then at = j break end
		end
		local chosen
		if at then
			chosen = lines[at]
		else
			-- the book move was not among the searched lines: score it with a short search
			stopFlag = false
			deadline = clock() + 0.05
			local e = { move = bookMove, score = -INF }
			local entry2, sc2, pv2 = rootWindow({ e }, math.max(3, math.min(finalDepth, 5)), -INF, INF)
			if entry2 then
				chosen = { move = bookMove, score = sc2, pv = pv2 }
			else
				chosen = { move = bookMove, score = topScore - 10, pv = { bookMove } }
			end
		end
		-- the engine's own evaluation has the last word: gambit lines are accepted up to the style's
		-- gambit margin, ordinary book moves only when they are close to the best move
		local margin = bookGambit and style.gambit or 100
		-- styles that do not love gambits only play one when the engine itself ranks it first
		local needsConsensus = bookGambit and style.gambit < 120 and at ~= 1
		if bookAlien and opts.alienGambits ~= false then
			margin = math.max(margin, 300) -- the engine still checks the position, but allows the gambit's cost
			needsConsensus = false
		end
		if needsConsensus or abs(topScore) >= MATE_BOUND or chosen.score < topScore - margin then
			bookRejected = true
		else
			if at then
				table.remove(lines, at)
			elseif #lines >= K then
				table.remove(lines)
			end
			if chosen.score < topScore then
				chosen.score = topScore -- keep the book move on top
			end
			table.insert(lines, 1, chosen)
			result.book = true
			if result.gambit and result.gambit.uci == bookUci then
				result.gambitPlayed = true
			end
		end
	end
	if bookRejected and not opts._retry then
		-- not trusting the book here: run a normal full-strength search instead
		local o = {}
		for k, v in pairs(opts) do o[k] = v end
		o.useBook, o._retry = false, true
		local again = searchCore(o)
		again.opening = result.opening
		again.gambit = result.gambit
		again.bookRejected = true
		return again
	end

	for j, entry in ipairs(lines) do
		local uci = {}
		for k2, mv in ipairs(entry.pv) do uci[k2] = moveToUci(mv) end
		result.lines[j] = { uci = moveToUci(entry.move), score = entry.score, depth = result.depth, pv = uci }
	end
	result.nodes = nodes
	result.elapsed = clock() - searchStart
	result.nps = result.elapsed > 0 and floor(nodes / result.elapsed) or 0
	result.cancelled = cancelFn ~= nil and cancelFn() == true
	result.timedOut = (not result.cancelled) and clock() >= deadline
	result.easy = easy
	result.seldepth = selDepth
	return result
end

------------------------------------------------------------------------------------------------
-- public entry point (guards the shared board state against overlapping searches)
------------------------------------------------------------------------------------------------
local running = false

function Claude1.isRunning()
	-- a search whose thread died (no heartbeat for 3 s) no longer counts as running
	return running and (clock() - lastBeat) < 3
end

function Claude1.search(opts)
	if Claude1.isRunning() then
		return { lines = {}, depth = 0, nodes = 0, elapsed = 0, nps = 0, busy = true }
	end
	running = true
	lastBeat = clock()
	local ok, result = pcall(searchCore, opts)
	running = false
	if not ok then
		return { lines = {}, depth = 0, nodes = 0, elapsed = 0, nps = 0, error = tostring(result) }
	end
	return result
end

------------------------------------------------------------------------------------------------
-- utilities (tests / host integration)
------------------------------------------------------------------------------------------------
local function perftRec(depth, list)
	if depth == 0 then
		return 1
	end
	local pseudo = MV[depth + 70] or {}
	MV[depth + 70] = pseudo
	local n = generate(pseudo, false)
	local total = 0
	local chk = inCheck()
	for i = 1, n do
		local m = pseudo[i]
		if makeMove(m, chk) then
			total = total + perftRec(depth - 1)
			unmakeMove(m)
		end
	end
	return total
end

function Claude1.perft(fen, depth)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	return perftRec(depth)
end

function Claude1.legalMoves(fen)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	local out = {}
	for i, m in ipairs(legalRootMoves()) do
		out[i] = moveToUci(m)
	end
	return out
end

function Claude1.evaluate(fen, styleOverride)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	style = STYLE_PARAMS[styleOverride or "Normal"] or STYLE_PARAMS.Normal
	rootSide = side
	local dmg, deg, scale = dynamicTerms()
	if not dmg then
		return 0
	end
	return whiteTotal(dmg, deg, scale)
end

function Claude1.positionKey(fen)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	return h1 .. "_" .. h2
end

function Claude1._testGivesCheck(fen, depth)
	if not setFen(fen) then return nil end
	local bad, total = 0, 0
	local function walk(d)
		local list = {}
		local n = generate(list, false)
		local chk = inCheck()
		for i = 1, n do
			local m = list[i]
			local from = m % 128
			local rest = m // 128
			local to = rest % 128
			local flag = (rest // 128) // 8
			if makeMove(m, chk) then
				total = total + 1
				if givesCheckAfter(from, to, flag, 3 - side) ~= inCheck() then bad = bad + 1 end
				if d > 1 then walk(d - 1) end
				unmakeMove(m)
			end
		end
	end
	walk(depth)
	return bad, total
end

function Claude1._testLists(fen, depth)
	if not setFen(fen) then return nil end
	local bad, nodes = 0, 0
	local function verify()
		local cnt = { 0, 0 }
		for sq = 22, 99 do
			local p = board[sq]
			if p ~= 0 and p ~= 16 then
				local c = PCOL[p]
				cnt[c] = cnt[c] + 1
				if PLS[c][PLIDX[sq]] ~= sq then bad = bad + 1 end
			end
		end
		if cnt[1] ~= PLNUM[1] or cnt[2] ~= PLNUM[2] then bad = bad + 1 end
	end
	local function walk(d)
		local list = {}
		local n = generate(list, false)
		local chk = inCheck()
		for i = 1, n do
			local m = list[i]
			if makeMove(m, chk) then
				nodes = nodes + 1
				verify()
				if d > 1 then walk(d - 1) end
				unmakeMove(m)
				verify()
			else
				verify()
			end
		end
	end
	verify()
	walk(depth)
	return bad, nodes
end

function Claude1.clearHash()
	for i = 1, TT_SIZE do
		ttKey[i], ttMove[i], ttScore[i], ttDepth[i], ttFlag[i] = 0, 0, 0, -1, 0
	end
	for i = 0, 32767 do
		HISTORY[i] = 0
	end
end

local function toFen()
	local rows = {}
	for r = 7, 0, -1 do
		local row, empty = {}, 0
		for f = 0, 7 do
			local p = board[sqOf(r, f)]
			if p == 0 then
				empty = empty + 1
			else
				if empty > 0 then row[#row + 1] = tostring(empty); empty = 0 end
				row[#row + 1] = PIECE_FEN[p]
			end
		end
		if empty > 0 then row[#row + 1] = tostring(empty) end
		rows[#rows + 1] = table.concat(row)
	end
	local c = ""
	if band(castle, 1) ~= 0 then c = c .. "K" end
	if band(castle, 2) ~= 0 then c = c .. "Q" end
	if band(castle, 4) ~= 0 then c = c .. "k" end
	if band(castle, 8) ~= 0 then c = c .. "q" end
	if c == "" then c = "-" end
	return table.concat(rows, "/") .. " " .. (side == 1 and "w" or "b") .. " " .. c .. " "
		.. (ep ~= 0 and sqName(ep) or "-") .. " " .. tostring(half) .. " " .. tostring(fullmove)
end

-- returns the FEN after playing `uci` from `fen`, or nil if the move is not legal
function Claude1.applyMove(fen, uci)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	for _, m in ipairs(legalRootMoves()) do
		if moveToUci(m) == uci then
			local mover = side
			makeMove(m)
			if mover == 2 then fullmove = fullmove + 1 end
			return toFen()
		end
	end
	return nil
end

-- "checkmate" | "stalemate" | "fifty" | "insufficient" | nil
function Claude1.gameState(fen)
	if Claude1.isRunning() or not setFen(fen) then
		return nil
	end
	if #legalRootMoves() == 0 then
		return inCheck() and "checkmate" or "stalemate"
	end
	if half >= 100 then
		return "fifty"
	end
	local pawns, minors, heavy = 0, 0, 0
	for r = 0, 7 do
		for f = 0, 7 do
			local t = PTYPE[board[sqOf(r, f)]]
			if t == 1 then pawns = pawns + 1 elseif t == 2 or t == 3 then minors = minors + 1 elseif t == 4 or t == 5 then heavy = heavy + 1 end
		end
	end
	if pawns == 0 and heavy == 0 and minors <= 1 then
		return "insufficient"
	end
	return nil
end

return Claude1
end)()

local EngineCore = {}

EngineCore.enginePreference = "Normal" EngineCore.enginePreferenceOrder =
Claude1.STYLES EngineCore.eloSkill = "Full"
EngineCore.eloSkillOrder = { "Full", "Expert", "Advanced",
"Intermediate", "Casual", "Beginner" } EngineCore.eloSkillProfiles = {
Full = { label = "FULL", minimumLoss = 0, maximumLoss = 0, estimated =
"maximum", }, Expert = { label = "EXPERT", minimumLoss = 0, maximumLoss
= 18, estimated = "2200+", qualitySafe = true, }, Advanced = { label =
"ADVANCED", minimumLoss = 0, maximumLoss = 35, estimated = "1800-ish",
qualitySafe = true, }, Intermediate = { label = "INTERMEDIATE",
minimumLoss = 0, maximumLoss = 90, estimated = "1400-ish", }, Casual = {
label = "CASUAL", minimumLoss = 0, maximumLoss = 180, estimated =
"1000-ish", }, Beginner = { label = "BEGINNER", minimumLoss = 0,
maximumLoss = 320, estimated = "600-ish", }, }
EngineCore.multiArrowEnabled = false EngineCore.rankedArrows = {}


EngineCore.MG_VALUE = { pawn = 100, knight = 325, bishop = 335, rook =
510, queen = 950, king = 20000, }

EngineCore.EG_VALUE = { pawn = 120, knight = 315, bishop = 345, rook =
525, queen = 930, king = 20000, }

EngineCore.PHASE_VALUE = { pawn = 0, knight = 1, bishop = 1, rook = 2,
queen = 4, king = 0, }

function EngineCore.moveKey(move) return tostring(move.fromFile) ..
tostring(move.fromRank) .. tostring(move.toFile) ..
tostring(move.toRank) .. (move.promotion or "") end

function EngineCore.sameMove(first, second) return first and second and
first.fromFile == second.fromFile and first.fromRank == second.fromRank
and first.toFile == second.toFile and first.toRank == second.toRank and
first.promotion == second.promotion end

 
function EngineCore.materialBalanceForSide(board, selectedSide) local
whiteMaterial = 0 local blackMaterial = 0

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece then
                local value = PIECE_VALUES[piece.kind] or 0
                if piece.kind ~= "king" then
                    if piece.color == "white" then
                        whiteMaterial += value
                    else
                        blackMaterial += value
                    end
                end
            end
        end
    end

    local whiteBalance = whiteMaterial - blackMaterial
    return selectedSide == "white" and whiteBalance or -whiteBalance

end

function EngineCore.rebindLegalCandidates(board, selectedSide,
candidates) local legalByKey = {} for _, legalMove in
ipairs(generateLegalMoves(board, selectedSide)) do
legalByKey[EngineCore.moveKey(legalMove)] = legalMove end

    local rebound = {}
    local seen = {}

    for _, candidate in ipairs(candidates or {}) do
        local key = candidate.move and EngineCore.moveKey(candidate.move) or nil
        local legalMove = key and legalByKey[key] or nil

        if legalMove and not seen[key] then
            local copy = {}
            for field, value in pairs(candidate) do
                copy[field] = value
            end
            copy.move = legalMove
            table.insert(rebound, copy)
            seen[key] = true
        end
    end

    return rebound

end

function EngineCore.candidatePassesImmediateSafety( board, selectedSide,
candidate, cancelCheck ) if not candidate or not candidate.move then
return false, "missing move", false end

    if cancelCheck and cancelCheck() then
        return false, "cancelled", true
    end

    local nextBoard = candidate.move._nextBoard
        or applyMove(board, candidate.move)

    if isKingInCheck(nextBoard, selectedSide) then
        return false, "leaves the king in check", false
    end

    local enemy = opposite(selectedSide)
    local replies = EngineCore.orderMoves(
        nextBoard,
        generateLegalMoves(nextBoard, enemy),
        nil,
        1,
        nil
    )

    -- Checkmate/stalemate cannot contain an immediate tactical refutation.
    if #replies == 0 then
        return true, nil, false
    end

    -- Captures, promotions, and checks are ordered first. Checking a bounded
    -- forcing set prevents the safety pass from freezing the client in high-
    -- mobility positions while still covering the replies most likely to win
    -- a queen or deliver mate.
    local replyLimit = math.min(20, #replies)

    local baseBalance = EngineCore.materialBalanceForSide(board, selectedSide)
    local worstDrop = 0
    local queenCaptured = false

    for index = 1, replyLimit do
        local reply = replies[index]
        if cancelCheck and cancelCheck() then
            return false, "cancelled", true
        end

        local replyBoard = reply._nextBoard or applyMove(nextBoard, reply)
        local legalResponses = generateLegalMoves(replyBoard, selectedSide)

        if #legalResponses == 0 and isKingInCheck(replyBoard, selectedSide) then
            return false, "allows mate in one", false
        end

        local balanceAfterReply = EngineCore.materialBalanceForSide(
            replyBoard,
            selectedSide
        )
        local materialDrop = baseBalance - balanceAfterReply
        if materialDrop > worstDrop then
            worstDrop = materialDrop
        end

        if reply.capture
            and reply.capture.color == selectedSide
            and reply.capture.kind == "queen" then
            queenCaptured = true
        end

        if index % 4 == 0 then
            task.wait()
        end
    end

    local score = tonumber(candidate.score) or 0
    local relativeScore = selectedSide == "white" and score or -score
    local winningMate = relativeScore >= MATE_SCORE - 500

    -- Only hard-reject illegal moves and confirmed mate-in-one losses. Material
    -- alarms are retained as ranking penalties instead of deleting every move.
    -- This prevents the safety layer from producing "no engine move found" in
    -- tactical positions where all returned lines contain a temporary sacrifice.
    candidate.safetyPenalty = 0
    candidate.safetyWarning = nil

    if not winningMate
        and queenCaptured
        and worstDrop >= 300
        and relativeScore < 350 then
        candidate.safetyPenalty = math.max(
            candidate.safetyPenalty,
            math.min(980, math.max(520, worstDrop - 80))
        )
        candidate.safetyWarning = "queen exposed after the opponent's best reply"
    end

    if not winningMate
        and worstDrop >= 700
        and relativeScore < 450 then
        candidate.safetyPenalty = math.max(candidate.safetyPenalty, 480)
        candidate.safetyWarning = candidate.safetyWarning
            or "large immediate material risk"
    end

    return true, candidate.safetyWarning, false

end

function EngineCore.filterSafetyCandidates( board, selectedSide,
candidates, cancelCheck ) local safe = {} local rejected = {} local
rebound = EngineCore.rebindLegalCandidates( board, selectedSide,
candidates )

    for _, candidate in ipairs(rebound) do
        local accepted, reason, wasCancelled =
            EngineCore.candidatePassesImmediateSafety(
                board,
                selectedSide,
                candidate,
                cancelCheck
            )

        if wasCancelled then
            return {}, rejected, true
        end

        if accepted then
            candidate.safetyVerified = true
            table.insert(safe, candidate)
        else
            table.insert(rejected, {
                move = candidate.move,
                reason = reason or "failed tactical safety check",
            })
        end
    end

    -- Keep the engine evaluation as the main signal, but demote candidates with
    -- an immediate tactical warning. A risky move remains available when it is
    -- the only legal/engine-backed option instead of causing an empty result.
    table.sort(safe, function(first, second)
        -- Cloud candidates are authoritative. Local quick/fallback scores use a
        -- different, much shallower evaluation scale and previously could jump
        -- above Stockfish merely because their raw number looked larger.
        local firstCloud = first.cloud == true
        local secondCloud = second.cloud == true
        if firstCloud ~= secondCloud then
            return firstCloud
        end

        local firstRelative = selectedSide == "white"
            and (tonumber(first.score) or 0)
            or -(tonumber(first.score) or 0)
        local secondRelative = selectedSide == "white"
            and (tonumber(second.score) or 0)
            or -(tonumber(second.score) or 0)
        local firstAdjusted = firstRelative
            - (tonumber(first.safetyPenalty) or 0)
            + (first.consensus and 24 or 0)
        local secondAdjusted = secondRelative
            - (tonumber(second.safetyPenalty) or 0)
            + (second.consensus and 24 or 0)

        if firstAdjusted == secondAdjusted then
            return firstRelative > secondRelative
        end
        return firstAdjusted > secondAdjusted
    end)

    return safe, rejected, false

end

  -- Claude 5's own search already ranks the final candidates, so the old second-engine
-- cross-check is no longer needed. Returning nil skips the extra re-filter at the call site.
function EngineCore.verifyCandidatePool( board, selectedSide, candidates,
modeName, cancelCheck )
    return nil, { depth = 0, nodes = 0 }, false
end

function EngineCore.captureQuality(board, move) if not move.capture then
return 0 end

    local captured = EngineCore.MG_VALUE[move.capture.kind] or 0
    local attacker = EngineCore.MG_VALUE[move.piece.kind] or 0
    local nextBoard = move._nextBoard or applyMove(board, move)
    local destinationAttacked = isSquareAttacked(
        nextBoard,
        move.toFile,
        move.toRank,
        opposite(move.piece.color)
    )
    local destinationDefended = isSquareAttacked(
        nextBoard,
        move.toFile,
        move.toRank,
        move.piece.color
    )

    local quality = captured * 16 - attacker
    if destinationAttacked then
        quality -= attacker * (destinationDefended and 0.45 or 1.0)
    end
    return quality

end

function EngineCore.moveOrderingScore(board, move, state, ply,
preferredMove) local score = 0

    if EngineCore.sameMove(move, preferredMove) then
        score += 20000000
    end

    if move.capture then
        score += 1000000 + EngineCore.captureQuality(board, move) * 32
    end

    if move.promotion then
        score += 1800000 + (EngineCore.MG_VALUE[move.promotion] or 0) * 100
    end

    local key = EngineCore.moveKey(move)
    local killers = state and state.killers[ply]
    if not move.capture and killers then
        if killers[1] == key then
            score += 900000
        elseif killers[2] == key then
            score += 800000
        end
    end

    if state then
        local counterKey = state.previousMoveKeys[ply]
        local counterMove = counterKey and state.counterMoves[counterKey]
        if counterMove == key then
            score += 750000
        end

        local history = state.history[move.piece.color]
        if history then
            score += history[key] or 0
        end
    end

    local centerDistance = math.abs(4.5 - move.toFile) + math.abs(4.5 - move.toRank)
    score += math.max(0, 12 - centerDistance * 2)

    local nextBoard = move._nextBoard or applyMove(board, move)
    if isKingInCheck(nextBoard, opposite(move.piece.color)) then
        score += 500000
    end

    return score

end

function EngineCore.orderMoves(board, moves, state, ply, preferredMove)
local scored = table.create(#moves)

    for index, move in ipairs(moves) do
        scored[index] = {
            move = move,
            order = EngineCore.moveOrderingScore(board, move, state, ply, preferredMove),
        }
    end

    table.sort(scored, function(first, second)
        return first.order > second.order
    end)

    local ordered = table.create(#moves)
    for index, entry in ipairs(scored) do
        ordered[index] = entry.move
    end
    return ordered

end

function EngineCore.sortCandidates(candidates, selectedSide)
table.sort(candidates, function(first, second) if selectedSide ==
"white" then return first.score > second.score end return first.score <
second.score end) end

function EngineCore.relativeCandidateScore(candidate, selectedSide)
local score = tonumber(candidate and candidate.score) or 0 return
selectedSide == "white" and score or -score end

function EngineCore.hashText(text) text = tostring(text or "") local
hash = 0

    for index = 1, #text do
        hash = (hash * 131 + string.byte(text, index)) % 2147483647
    end

    return hash

end

function EngineCore.applyEloSkill(board, selectedSide, candidates) if
EngineCore.eloSkill == "Full" or not candidates or #candidates <= 1 then
return candidates end

    local profile = EngineCore.eloSkillProfiles[EngineCore.eloSkill]
    if not profile then
        EngineCore.eloSkill = "Full"
        return candidates
    end

    local pool = {}
    for _, candidate in ipairs(candidates) do
        if candidate and candidate.move then
            local copy = {}
            for key, value in pairs(candidate) do
                if key ~= "eloPrimary"
                    and key ~= "fullStrengthBest"
                    and key ~= "eloSkill"
                    and key ~= "eloLoss"
                    and key ~= "eloEstimated" then
                    copy[key] = value
                end
            end
            table.insert(pool, copy)
        end
    end

    if #pool <= 1 then
        return pool
    end

    table.sort(pool, function(first, second)
        local firstRelative = EngineCore.relativeCandidateScore(first, selectedSide)
        local secondRelative = EngineCore.relativeCandidateScore(second, selectedSide)
        if firstRelative == secondRelative then
            return EngineCore.moveKey(first.move) < EngineCore.moveKey(second.move)
        end
        return firstRelative > secondRelative
    end)

    local fullStrengthBest = pool[1]
    local bestRelative = EngineCore.relativeCandidateScore(fullStrengthBest, selectedSide)

    -- Never weaken a forced mate/winning king-capture line. Elo Skill is a
    -- training selector, not a tactical blunder generator.
    if math.abs(bestRelative) >= MATE_SCORE - 500
        or fullStrengthBest.move.kingCapture then
        return pool
    end

    local minimumLoss = tonumber(profile.minimumLoss) or 0
    local maximumLoss = tonumber(profile.maximumLoss) or 0
    local seed = EngineCore.hashText(
        boardHash(board, selectedSide)
            .. ":"
            .. BoardTracker.fenStateKey()
            .. ":"
            .. selectedSide
            .. ":"
            .. tostring(EngineCore.eloSkill)
    )
    local targetLoss = minimumLoss
    if maximumLoss > minimumLoss then
        targetLoss += seed % (maximumLoss - minimumLoss + 1)
    end

    -- Quality-safe presets should mostly behave like Full Strength. They only
    -- choose an alternate move when it is genuinely close to the engine's best
    -- verified move. This keeps Advanced/Expert from turning the feature into a
    -- mistake generator while still allowing realistic variety.
    if profile.qualitySafe and targetLoss > maximumLoss * 0.55 then
        targetLoss = math.floor(maximumLoss * 0.55)
    end

    local chosen = fullStrengthBest
    local chosenDistance = math.huge

    for index, candidate in ipairs(pool) do
        local relative = EngineCore.relativeCandidateScore(candidate, selectedSide)
        local loss = math.max(0, bestRelative - relative)
        local safetyPenalty = tonumber(candidate.safetyPenalty) or 0
        local severeWarning = candidate.safetyWarning ~= nil or safetyPenalty >= 220
        local mateLoss = candidate.verificationMateLoss == true
            or relative <= (-MATE_SCORE + 500)
        local majorDrop = loss >= math.max(120, maximumLoss * 2)

        -- Keep every preset legal and tactically sane. Weak levels may choose a
        -- lower-ranked move, but they are not allowed to pick proven mate losses,
        -- immediate queen hangs, severe safety warnings, or large drops from the
        -- verified best line.
        if not mateLoss and not severeWarning and not majorDrop and loss <= maximumLoss then
            local distance = math.abs(loss - targetLoss)
            if distance < chosenDistance
                or (distance == chosenDistance
                    and EngineCore.moveKey(candidate.move)
                        < EngineCore.moveKey(chosen.move)) then
                chosen = candidate
                chosenDistance = distance
            end
        end
    end

    if chosen ~= fullStrengthBest then
        chosen.eloPrimary = true
        chosen.eloSkill = EngineCore.eloSkill
        chosen.eloEstimated = profile.estimated
        chosen.eloLoss = math.max(
            0,
            bestRelative - EngineCore.relativeCandidateScore(chosen, selectedSide)
        )
        fullStrengthBest.fullStrengthBest = true
    end

    local reordered = { chosen }
    for _, candidate in ipairs(pool) do
        if candidate ~= chosen then
            table.insert(reordered, candidate)
        end
    end

    return reordered

end

function EngineCore.boardToFen(board, selectedSide) local rows = {}
local symbols = { pawn = "p", knight = "n", bishop = "b", rook = "r",
queen = "q", king = "k", }

    for rank = 8, 1, -1 do
        local row = {}
        local emptyCount = 0

        for file = 1, 8 do
            local piece = board[rank][file]
            if not piece then
                emptyCount += 1
            else
                if emptyCount > 0 then
                    table.insert(row, tostring(emptyCount))
                    emptyCount = 0
                end

                local symbol = symbols[piece.kind]
                if piece.color == "white" then
                    symbol = string.upper(symbol)
                end
                table.insert(row, symbol)
            end
        end

        if emptyCount > 0 then
            table.insert(row, tostring(emptyCount))
        end
        table.insert(rows, table.concat(row))
    end

    return table.concat(rows, "/")
        .. " "
        .. (selectedSide == "white" and "w" or "b")
        .. " "
        .. BoardTracker.castlingString()
        .. " "
        .. (BoardTracker.enPassantSquare or "-")
        .. " "
        .. tostring(BoardTracker.halfmoveClock or 0)
        .. " "
        .. tostring(BoardTracker.fullmoveNumber or 1)

end

function EngineCore.findLegalMoveByUci(board, color, uci) if type(uci)
~= "string" then return nil end

    uci = string.lower(uci)
    if #uci < 4 then
        return nil
    end

    local fromFile = string.byte(string.sub(uci, 1, 1)) - 96
    local fromRank = tonumber(string.sub(uci, 2, 2))
    local toFile = string.byte(string.sub(uci, 3, 3)) - 96
    local toRank = tonumber(string.sub(uci, 4, 4))
    local promotionLetter = string.sub(uci, 5, 5)
    local promotion = nil

    if promotionLetter == "q" then
        promotion = "queen"
    elseif promotionLetter == "r" then
        promotion = "rook"
    elseif promotionLetter == "b" then
        promotion = "bishop"
    elseif promotionLetter == "n" then
        promotion = "knight"
    end

    if not inBounds(fromFile, fromRank) or not inBounds(toFile, toRank) then
        return nil
    end

    for _, move in ipairs(generateLegalMoves(board, color)) do
        if move.fromFile == fromFile
            and move.fromRank == fromRank
            and move.toFile == toFile
            and move.toRank == toRank
            and move.promotion == promotion then
            return move
        end
    end

    return nil

end

local OpeningBook = { enabled = true, repertoireName = "Twitchy's Ruy Lopez Repertoire",   lines = { { name = "Ruy Lopez: Morphy Defense, Closed setup", moves = { "e2e4", "e7e5", "g1f3", "b8c6",
"f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7", "f1e1", "b7b5", "a4b3",
"d7d6", "c2c3", "e8g8", "h2h3", }, }, { name = "Ruy Lopez: Berlin Defense", moves = { "e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "g8f6",
"e1g1", "f6e4", "d2d4", "e4d6", "b5c6", "d7c6", "d4e5", "d6f5", "d1d8",
"e8d8", }, }, { name = "Ruy Lopez: Exchange Variation", moves = {
"e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5c6", "d7c6", "e1g1",
"f7f6", "d2d4", "e5d4", "f3d4", "c6c5", "d4b3", }, }, { name = "Ruy Lopez: Open Variation", moves = { "e2e4", "e7e5", "g1f3", "b8c6",
"f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f6e4", "d2d4", "b7b5", "a4b3",
"d7d5", "d4e5", "c8e6", }, }, { name = "Ruy Lopez: Steinitz Defense",
moves = { "e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "d7d6", "d2d4",
"c8d7", "b1c3", "g8f6", "e1g1", "f8e7", "f1e1", }, }, { name = "Ruy Lopez: Anti-Marshall setup", moves = { "e2e4", "e7e5", "g1f3", "b8c6",
"f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7", "f1e1", "b7b5", "a4b3",
"e8g8", "a2a4", }, }, { name = "Italian fallback when Bb5 is not chosen", moves = { "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6",
"d2d3", "f8c5", "c2c3", "d7d6", "b1d2", "a7a6", "c4b3", }, }, { name =
"Open Sicilian fallback", moves = { "e2e4", "c7c5", "g1f3", "d7d6",
"d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6", "f1e2", }, }, { name =
"French Defense: Tarrasch setup", moves = { "e2e4", "e7e6", "d2d4",
"d7d5", "b1d2", "g8f6", "e4e5", "f6d7", "f1d3", "c7c5", "c2c3", }, }, {
name = "Caro-Kann Advance setup", moves = { "e2e4", "c7c6", "d2d4",
"d7d5", "e4e5", "c8f5", "g1f3", "e7e6", "f1e2", "c6c5", "c2c3", }, }, {
name = "Scandinavian: main capture line", moves = { "e2e4", "d7d5",
"e4d5", "d8d5", "b1c3", "d5d6", "d2d4", "g8f6", "g1f3", }, }, { name =
"Pirc/Modern setup", moves = { "e2e4", "d7d6", "d2d4", "g8f6", "b1c3",
"g7g6", "g1f3", "f8g7", "f1e2", }, }, { name = "Queen's Gambit Declined for Black", moves = { "d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6",
"c1g5", "f8e7", "e2e3", "h7h6", "g5h4", }, }, { name = "London System for Black", moves = { "d2d4", "d7d5", "g1f3", "g8f6", "c1f4", "e7e6",
"e2e3", "f8d6", "f4d6", "d8d6", "c2c4", "c7c6", }, }, { name = "English Opening: solid Black setup", moves = { "c2c4", "g8f6", "g1f3", "e7e6",
"g2g3", "d7d5", "f1g2", "f8e7", }, }, }, }

function OpeningBook.createStartingBoard() local board =
createEmptyBoard() local backRank = { "rook", "knight", "bishop",
"queen", "king", "bishop", "knight", "rook", }

    for file, kind in ipairs(backRank) do
        board[1][file] = { color = "white", kind = kind }
        board[8][file] = { color = "black", kind = kind }
    end

    for file = 1, 8 do
        board[2][file] = { color = "white", kind = "pawn" }
        board[7][file] = { color = "black", kind = "pawn" }
    end

    return board

end

function OpeningBook.applyBookMove(board, color, uci) if type(uci) ~=
"string" or #uci < 4 then return nil end

    local fromFile = string.byte(string.sub(uci, 1, 1)) - 96
    local fromRank = tonumber(string.sub(uci, 2, 2))
    local toFile = string.byte(string.sub(uci, 3, 3)) - 96
    local toRank = tonumber(string.sub(uci, 4, 4))
    local promotionLetter = string.sub(uci, 5, 5)
    local promotion = nil

    if promotionLetter == "q" then
        promotion = "queen"
    elseif promotionLetter == "r" then
        promotion = "rook"
    elseif promotionLetter == "b" then
        promotion = "bishop"
    elseif promotionLetter == "n" then
        promotion = "knight"
    end

    if not inBounds(fromFile, fromRank) or not inBounds(toFile, toRank) then
        return nil
    end

    local piece = board[fromRank] and board[fromRank][fromFile]
    if not piece or piece.color ~= color then
        return nil
    end

    local nextBoard = cloneBoard(board)
    nextBoard[fromRank][fromFile] = nil

    if piece.kind == "king" and math.abs(toFile - fromFile) == 2 then
        local rookFromFile = toFile > fromFile and 8 or 1
        local rookToFile = toFile > fromFile and 6 or 4
        local rook = nextBoard[fromRank][rookFromFile]
        nextBoard[fromRank][rookFromFile] = nil
        if rook then
            nextBoard[fromRank][rookToFile] = {
                color = rook.color,
                kind = rook.kind,
                instance = rook.instance,
            }
        end
    end

    nextBoard[toRank][toFile] = {
        color = piece.color,
        kind = promotion or piece.kind,
        instance = piece.instance,
    }

    return nextBoard

end

function OpeningBook.positionMatches(firstBoard, secondBoard) return
firstBoard and secondBoard and BoardTracker.pieceHash(firstBoard) ==
BoardTracker.pieceHash(secondBoard) end

function OpeningBook.makeCandidate(board, selectedSide, line, nextUci,
replyUci, plyIndex) local move = EngineCore.findLegalMoveByUci(board,
selectedSide, nextUci) if not move then return nil end

    local nextBoard = move._nextBoard or applyMove(board, move)
    local reply = replyUci
        and EngineCore.findLegalMoveByUci(nextBoard, opposite(selectedSide), replyUci)
        or nil

    return {
        move = move,
        reply = reply,
        score = EngineCore.evaluateBoard(nextBoard, opposite(selectedSide)),
        depth = 0,
        book = true,
        opening = line.name,
        repertoire = OpeningBook.repertoireName,
        linePly = plyIndex or 0,
    }

end

function OpeningBook.findCandidates(board, selectedSide) if not
OpeningBook.enabled or not board or not selectedSide then return nil,
nil end

    local candidates = {}
    local seen = {}

    for _, line in ipairs(OpeningBook.lines) do
        local workingBoard = OpeningBook.createStartingBoard()
        local colorToMove = "white"

        for plyIndex = 0, #line.moves do
            if OpeningBook.positionMatches(workingBoard, board)
                and colorToMove == selectedSide then
                local nextUci = line.moves[plyIndex + 1]
                if nextUci and not seen[nextUci] then
                    local candidate = OpeningBook.makeCandidate(
                        board,
                        selectedSide,
                        line,
                        nextUci,
                        line.moves[plyIndex + 2],
                        plyIndex
                    )
                    if candidate then
                        table.insert(candidates, candidate)
                        seen[nextUci] = true
                        if #candidates >= TOP_MOVE_COUNT then
                            break
                        end
                    end
                end
            end

            local playedUci = line.moves[plyIndex + 1]
            if not playedUci or #candidates >= TOP_MOVE_COUNT then
                break
            end

            local nextWorkingBoard = OpeningBook.applyBookMove(
                workingBoard,
                colorToMove,
                playedUci
            )
            if not nextWorkingBoard then
                break
            end

            workingBoard = nextWorkingBoard
            colorToMove = opposite(colorToMove)
        end

        if #candidates >= TOP_MOVE_COUNT then
            break
        end
    end

    if #candidates == 0 then
        return nil, nil
    end

    local info = {
        depth = 0,
        nodes = 0,
        elapsed = 0,
        timedOut = false,
        provider = "Opening Book",
        book = true,
        openingName = candidates[1].opening,
        repertoire = OpeningBook.repertoireName,
        tacticalVerified = true,
    }

    return candidates, info

end

function OpeningBook.describePosition(board, selectedSide) local
candidates, info = OpeningBook.findCandidates(board, selectedSide) if
candidates and candidates[1] then return "Repertoire:" .. (info and
info.repertoire or OpeningBook.repertoireName) .. " — " ..
candidates[1].opening end

    return nil

end

EngineCore.analysisPlanCache = {} EngineCore.analysisPlanOrder = {}
EngineCore.analysisPlanLimit = 96

function EngineCore.analysisPlanKey(board, selectedSide, modeName)
return boardHash(board, selectedSide) .. ":" ..
BoardTracker.fenStateKey() .. ":" .. selectedSide .. ":" ..
tostring(modeName) .. ":" .. tostring(EngineCore.enginePreference) ..
":" .. tostring(EngineCore.eloSkill) end

function EngineCore.storeAnalysisPlanEntry(key, entry) if not
EngineCore.analysisPlanCache[key] then
table.insert(EngineCore.analysisPlanOrder, key) end

    EngineCore.analysisPlanCache[key] = entry

    while #EngineCore.analysisPlanOrder > EngineCore.analysisPlanLimit do
        local oldestKey = table.remove(EngineCore.analysisPlanOrder, 1)
        EngineCore.analysisPlanCache[oldestKey] = nil
    end

end

function EngineCore.serializeCandidate(candidate) if not candidate or
not candidate.move then return nil end

    return {
        move = moveToCoordinates(candidate.move),
        reply = candidate.reply and moveToCoordinates(candidate.reply) or nil,
        score = candidate.score,
        depth = candidate.depth,
        cloud = candidate.cloud == true,
    }

end

function EngineCore.deserializeCandidates(board, selectedSide,
serializedCandidates) local candidates = {}

    for _, serialized in ipairs(serializedCandidates or {}) do
        local move = EngineCore.findLegalMoveByUci(board, selectedSide, serialized.move)
        if move then
            local reply = nil
            if serialized.reply then
                local nextBoard = move._nextBoard or applyMove(board, move)
                reply = EngineCore.findLegalMoveByUci(
                    nextBoard,
                    opposite(selectedSide),
                    serialized.reply
                )
            end

            table.insert(candidates, {
                move = move,
                reply = reply,
                score = serialized.score,
                depth = serialized.depth,
                cloud = serialized.cloud == true,
                planned = true,
            })
        end
    end

    return candidates

end

function EngineCore.getPlannedAnalysis(board, selectedSide, modeName)
local key = EngineCore.analysisPlanKey(board, selectedSide, modeName)
local entry = EngineCore.analysisPlanCache[key] if not entry then return
nil, nil end

    local candidates = EngineCore.deserializeCandidates(
        board,
        selectedSide,
        entry.candidates
    )

    if #candidates == 0 then
        EngineCore.analysisPlanCache[key] = nil
        return nil, nil
    end

    return candidates, {
        depth = entry.depth or candidates[1].depth or 0,
        nodes = 0,
        elapsed = 0,
        timedOut = false,
        cloud = entry.cloud == true,
        planned = true,
    }

end

function EngineCore.rememberPrincipalLine( board, selectedSide,
modeName, line, depth, cloud ) if type(line) ~= "table" or #line < 3
then return end

    local workingBoard = board
    local colorToMove = selectedSide

    for index, uci in ipairs(line) do
        local move = EngineCore.findLegalMoveByUci(workingBoard, colorToMove, uci)
        if not move then
            break
        end

        if colorToMove == selectedSide and index > 1 then
            local nextBoard = move._nextBoard or applyMove(workingBoard, move)
            local reply = nil
            local evaluationBoard = nextBoard

            if line[index + 1] then
                reply = EngineCore.findLegalMoveByUci(
                    nextBoard,
                    opposite(selectedSide),
                    line[index + 1]
                )
                if reply then
                    evaluationBoard = reply._nextBoard or applyMove(nextBoard, reply)
                end
            end

            local candidate = {
                move = move,
                reply = reply,
                score = EngineCore.evaluateBoard(evaluationBoard, selectedSide),
                depth = math.max(1, (depth or #line) - index + 1),
                cloud = cloud == true,
            }
            local serialized = EngineCore.serializeCandidate(candidate)
            if serialized then
                EngineCore.storeAnalysisPlanEntry(
                    EngineCore.analysisPlanKey(workingBoard, selectedSide, modeName),
                    {
                        candidates = { serialized },
                        depth = candidate.depth,
                        cloud = cloud == true,
                    }
                )
            end
        end

        workingBoard = move._nextBoard or applyMove(workingBoard, move)
        colorToMove = opposite(colorToMove)
    end

end

function EngineCore.rememberAnalysis( board, selectedSide, modeName,
candidates, searchInfo ) local serializedCandidates = {} for _,
candidate in ipairs(candidates or {}) do local serialized =
EngineCore.serializeCandidate(candidate) if serialized then
table.insert(serializedCandidates, serialized) end end

    if #serializedCandidates == 0 then
        return
    end

    local best = candidates[1]
    if best and type(best.line) == "table" then
        EngineCore.rememberPrincipalLine(
            board,
            selectedSide,
            modeName,
            best.line,
            searchInfo and searchInfo.depth or best.depth,
            searchInfo and searchInfo.cloud or best.cloud
        )
    end

    EngineCore.storeAnalysisPlanEntry(
        EngineCore.analysisPlanKey(board, selectedSide, modeName),
        {
            candidates = serializedCandidates,
            depth = searchInfo and searchInfo.depth or best.depth,
            cloud = searchInfo and searchInfo.cloud == true or best.cloud == true,
        }
    )

end

-- ============================================================================
-- Claude 5 integration: engine glue, pondering, stable premove, gambit awareness, clock-aware time,
-- input-mismatch recovery and a game recorder for post-mortem analysis.
-- Everything below is local: no HTTP, no Stockfish, no Lichess.
-- ============================================================================
EngineCore.CLAUDE_YIELD_INTERVAL = 0.014
EngineCore.CLAUDE_YIELD_MIN = 0.010
EngineCore.CLAUDE_YIELD_MAX = 0.028
EngineCore.PONDER_YIELD_MIN = 0.005 -- background thinking uses smaller slices so the game stays smooth
EngineCore.PONDER_YIELD_MAX = 0.012

EngineCore.bestMoveOnly = false
EngineCore.ponderEnabled = false
EngineCore.premoveEnabled = false
EngineCore.ponderGeneration = 0
EngineCore.ponderPositionKey = nil
EngineCore.premove = { move = nil, uci = nil, tableData = nil }
EngineCore.ponderPlans = {}
EngineCore.ponderPlanOrder = {}

-- Plain material count (white-centric). Only used while Claude 3 is busy searching,
-- because the engine owns one shared board and must never be re-entered.
function EngineCore.materialBalance(board)
    local total = 0
    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece and piece.kind ~= "king" then
                local value = PIECE_VALUES[piece.kind] or 0
                if piece.color == "white" then
                    total = total + value
                else
                    total = total - value
                end
            end
        end
    end
    return total
end

-- Static evaluation (white-centric centipawns) from Claude 3's evaluation function.
function EngineCore.evaluateBoard(board, colorToMove)
    if not Claude1.isRunning() then
        local fen = EngineCore.boardToFen(board, colorToMove)
        local score = Claude1.evaluate(fen, "Normal")
        if score then
            return score
        end
    end
    return EngineCore.materialBalance(board)
end

-- Claude 3 reports side-to-move centipawns and mates as +/-(30000 - plies).
-- The hub stores WHITE-centric scores with mates as +/-(MATE_SCORE - plies).
function EngineCore.claudeScoreToHub(score, selectedSide)
    local hubScore = score
    if math.abs(score) > 29700 then
        local plies = 30000 - math.abs(score)
        hubScore = (score > 0 and 1 or -1) * (MATE_SCORE - plies)
    end
    if selectedSide == "black" then
        hubScore = -hubScore
    end
    return hubScore
end

function EngineCore.claudeLinesToCandidates(board, selectedSide, lines)
    local candidates = {}
    local enemy = opposite(selectedSide)

    for _, line in ipairs(lines or {}) do
        local move = EngineCore.findLegalMoveByUci(board, selectedSide, line.uci)
        if move then
            local reply = nil
            if line.pv and line.pv[2] then
                local nextBoard = move._nextBoard or applyMove(board, move)
                reply = EngineCore.findLegalMoveByUci(nextBoard, enemy, line.pv[2])
            end

            table.insert(candidates, {
                move = move,
                reply = reply,
                score = EngineCore.claudeScoreToHub(line.score, selectedSide),
                depth = line.depth,
                line = line.pv,
                provider = "Claude 5",
            })
        end
    end

    return candidates
end

-- Runs one Claude 3 search. Waits briefly for a previous (cancelled) search to
-- finish unwinding, because the engine's board state is shared.
-- options.fen overrides the FEN built from `board` (used for hypothetical positions).
function EngineCore.claudeSearch(board, selectedSide, options)
    local cancelCheck = options.cancelCheck

    local waitStarted = os.clock()
    while Claude1.isRunning() do
        if (cancelCheck and cancelCheck()) or os.clock() - waitStarted > 2.5 then
            return nil
        end
        task.wait()
    end

    return Claude1.search({
        fen = options.fen or EngineCore.boardToFen(board, selectedSide),
        timeLimit = options.timeLimit,
        softLimit = options.softLimit,
        maxDepth = options.maxDepth,
        minDepth = options.minDepth,
        easyMinDepth = options.easyMinDepth,
        easyMargin = options.easyMargin,
        easyReduce = options.easyReduce,
        qchecks = options.qchecks,
        singular = options.singular,
        useBook = options.useBook,
        multiPV = options.multiPV or TOP_MOVE_COUNT,
        style = options.style or EngineCore.enginePreference,
        yield = task.wait,
        yieldEvery = EngineCore.CLAUDE_YIELD_INTERVAL,
        yieldMin = options.yieldMin or EngineCore.CLAUDE_YIELD_MIN,
        yieldMax = options.yieldMax or EngineCore.CLAUDE_YIELD_MAX,
        cancel = cancelCheck,
        onProgress = options.onProgress,
    })
end

-- Cheap unranked list used only if the engine is unavailable (error / busy).
function EngineCore.staticRootCandidates(board, selectedSide)
    local candidates = {}
    local enemy = opposite(selectedSide)

    for _, move in ipairs(generateLegalMoves(board, selectedSide)) do
        local nextBoard = move._nextBoard or applyMove(board, move)
        table.insert(candidates, {
            move = move,
            reply = nil,
            score = EngineCore.evaluateBoard(nextBoard, enemy),
            depth = 0,
            provisional = true,
            provider = "Static",
        })
    end

    EngineCore.sortCandidates(candidates, selectedSide)
    while #candidates > TOP_MOVE_COUNT do
        table.remove(candidates)
    end
    return candidates
end

-- Short Claude 3 search used by the safety / recovery code paths.
function EngineCore.fallbackRootCandidates(board, selectedSide, options)
    options = options or {}
    local budget = math.max(0.06, (options.deadline or (os.clock() + 0.3)) - os.clock())

    local result = EngineCore.claudeSearch(board, selectedSide, {
        timeLimit = budget,
        maxDepth = 10,
        multiPV = TOP_MOVE_COUNT,
        cancelCheck = options.cancelCheck,
        qchecks = false,
        singular = false,
    })

    local candidates = {}
    if result and result.lines and #result.lines > 0 then
        candidates = EngineCore.claudeLinesToCandidates(board, selectedSide, result.lines)
    end
    if #candidates == 0 then
        candidates = EngineCore.staticRootCandidates(board, selectedSide)
    end
    return candidates
end

-- ----------------------------------------------------------------------------
-- Pondered analyses: stored under a key that does not depend on the live board's
-- castling / en-passant state (that state belongs to the position we are NOT in yet).
-- ----------------------------------------------------------------------------
function EngineCore.ponderKey(board, side, modeName)
    return boardHash(board, side) .. ":" .. side .. ":" .. tostring(modeName) .. ":"
        .. tostring(EngineCore.enginePreference) .. ":" .. tostring(EngineCore.eloSkill)
end

function EngineCore.storePonderPlan(board, side, modeName, candidates, depth, opening, gambit)
    local serialized = {}
    for _, candidate in ipairs(candidates) do
        local entry = EngineCore.serializeCandidate(candidate)
        if entry then
            table.insert(serialized, entry)
        end
    end
    if #serialized == 0 then
        return
    end
    local key = EngineCore.ponderKey(board, side, modeName)
    local existing = EngineCore.ponderPlans[key]
    if existing and (existing.depth or 0) > (depth or 0) then
        return -- keep the deeper analysis
    end
    if not existing then
        table.insert(EngineCore.ponderPlanOrder, key)
        while #EngineCore.ponderPlanOrder > 40 do
            EngineCore.ponderPlans[table.remove(EngineCore.ponderPlanOrder, 1)] = nil
        end
    end
    EngineCore.ponderPlans[key] = { candidates = serialized, depth = depth, opening = opening, gambit = gambit }
end

local baseGetPlannedAnalysis = EngineCore.getPlannedAnalysis
function EngineCore.getPlannedAnalysis(board, selectedSide, modeName)
    local entry = EngineCore.ponderPlans[EngineCore.ponderKey(board, selectedSide, modeName)]
    if entry then
        local list = EngineCore.deserializeCandidates(board, selectedSide, entry.candidates)
        if #list > 0 then
            return list, {
                depth = entry.depth or 0,
                nodes = 0,
                elapsed = 0,
                timedOut = false,
                planned = true,
                pondered = true,
                opening = entry.opening,
                gambit = entry.gambit,
                provider = "Claude 5 (pondered)",
            }
        end
    end
    return baseGetPlannedAnalysis(board, selectedSide, modeName)
end

-- ----------------------------------------------------------------------------
-- Searching
-- ----------------------------------------------------------------------------
local function searchTopMoves( board, selectedSide, modeName,
progressCallback, cancelCheck )
    local function cancelled()
        return cancelCheck and cancelCheck()
    end

    local startedAt = os.clock()

    local function cancelledResult(nodes)
        return {}, {
            depth = 0,
            nodes = nodes or 0,
            elapsed = os.clock() - startedAt,
            timedOut = false,
            cancelled = true,
            provider = "Claude 5",
        }
    end

    if cancelled() then
        return cancelledResult(0)
    end

    local bookCandidates, bookInfo = OpeningBook.findCandidates(board, selectedSide)
    if bookCandidates then
        return bookCandidates, bookInfo
    end

    local plannedCandidates, plannedInfo = EngineCore.getPlannedAnalysis(
        board,
        selectedSide,
        modeName
    )
    if plannedCandidates then
        return plannedCandidates, plannedInfo
    end

    local mode = ENGINE_MODES[modeName] or ENGINE_MODES.Blitz
    local rootMoves = generateLegalMoves(board, selectedSide)
    if #rootMoves == 0 then
        return {}, {
            depth = 0,
            nodes = 0,
            elapsed = os.clock() - startedAt,
            timedOut = false,
        }
    end

    local style = EngineCore.enginePreference
    local phaseText = "Claude 5 (" .. style .. ") searching"
    local lineCount = EngineCore.bestMoveOnly and 1 or TOP_MOVE_COUNT

    -- budget the thinking time from the real clock so the engine can never lose on time
    local hardLimit, softLimit = mode.timeLimit, mode.softLimit
    local myClock = selectedSide == "white" and BoardTracker.lastWhiteClock or BoardTracker.lastBlackClock
    if type(myClock) ~= "number" or myClock <= 0 then
        hardLimit = math.min(hardLimit, 7.0) -- clock unreadable: never think for more than 7 s
        softLimit = math.min(softLimit, 3.0)
    end
    if type(myClock) == "number" and myClock > 0 then
        hardLimit = math.min(hardLimit, math.max(0.25, myClock / 14))
        softLimit = math.min(softLimit, math.max(0.08, myClock / 45))
        if myClock < 25 then
            softLimit = math.min(softLimit, 0.12)
            hardLimit = math.min(hardLimit, 0.35)
        end
        if myClock < 8 then
            softLimit, hardLimit = 0.05, 0.15
        end
    end

    local result = EngineCore.claudeSearch(board, selectedSide, {
        timeLimit = hardLimit,
        softLimit = softLimit,
        maxDepth = mode.maxDepth,
        minDepth = math.min(mode.minDepth, (myClock and myClock < 25) and 2 or mode.minDepth),
        easyMinDepth = mode.easyMinDepth,
        easyMargin = mode.easyMargin,
        easyReduce = mode.easyReduce,
        qchecks = mode.qchecks,
        singular = mode.singular,
        multiPV = lineCount,
        style = style,
        cancelCheck = cancelCheck,
        onProgress = function(snapshot)
            if cancelled() or not progressCallback then
                return
            end
            local partial = EngineCore.claudeLinesToCandidates(
                board,
                selectedSide,
                snapshot.lines
            )
            if #partial == 0 then
                return
            end
            for _, candidate in ipairs(partial) do
                candidate.provisional = true
            end
            pcall(progressCallback, partial, {
                depth = snapshot.depth,
                nodes = snapshot.nodes,
                elapsed = snapshot.elapsed,
                provider = "Claude 5",
                phase = phaseText,
                thinking = true,
            })
        end,
    })

    if cancelled() then
        return cancelledResult(result and result.nodes or 0)
    end

    local candidates = {}
    if result and result.lines and #result.lines > 0 then
        candidates = EngineCore.claudeLinesToCandidates(board, selectedSide, result.lines)
    end

    local provider = "Claude 5"
    if result and result.error then
        warn("[Claude 5] search error: " .. tostring(result.error))
    end

    -- The engine proposed moves the game's own rules reject: the castling / en-passant state we
    -- built from the board is probably wrong. Re-search with the conservative state ("-" / "-")
    -- instead of falling back to weak static moves.
    local neededLines = math.min(lineCount, #rootMoves)
    if result and result.lines and #candidates < neededLines then
        local mapped = {}
        for _, candidate in ipairs(candidates) do
            mapped[moveToCoordinates(candidate.move)] = true
        end
        local rejected = {}
        for _, line in ipairs(result.lines) do
            if not mapped[line.uci] then
                table.insert(rejected, line.uci)
            end
        end
        EngineCore.logEvent("INPUT MISMATCH: engine moves rejected by the game rules: " .. table.concat(rejected, " ")
            .. " | fen " .. EngineCore.boardToFen(board, selectedSide))
        local safeFen = (string.gsub(EngineCore.boardToFen(board, selectedSide), "^(%S+ %S+) %S+ %S+ (.*)$", "%1 - - %2"))
        local retry = EngineCore.claudeSearch(board, selectedSide, {
            fen = safeFen,
            timeLimit = math.min(hardLimit, 1.0), softLimit = math.min(softLimit, 0.4),
            maxDepth = mode.maxDepth, multiPV = lineCount, style = style, useBook = false,
            qchecks = mode.qchecks, singular = mode.singular, cancelCheck = cancelCheck,
        })
        if retry and retry.lines and #retry.lines > 0 then
            local again = EngineCore.claudeLinesToCandidates(board, selectedSide, retry.lines)
            if #again > #candidates then
                candidates, result = again, retry
                EngineCore.logEvent("INPUT MISMATCH recovered with conservative castling/en-passant state.")
            end
        end
    end

    -- Fill any slot the engine could not provide (or all of them if it failed).
    local wanted = math.min(lineCount, #rootMoves)
    if #candidates < wanted then
        local used = {}
        for _, candidate in ipairs(candidates) do
            used[EngineCore.moveKey(candidate.move)] = true
        end
        for _, candidate in ipairs(EngineCore.staticRootCandidates(board, selectedSide)) do
            if #candidates >= wanted then
                break
            end
            local key = EngineCore.moveKey(candidate.move)
            if not used[key] then
                used[key] = true
                table.insert(candidates, candidate)
            end
        end
        if not result or #result.lines == 0 then
            provider = "Static fallback"
        end
    end

    local info = {
        depth = result and result.depth or 0,
        nodes = result and result.nodes or 0,
        elapsed = os.clock() - startedAt,
        timedOut = result ~= nil and result.timedOut == true,
        provider = provider,
        engine = "Claude 5",
        style = style,
        nps = result and result.nps or 0,
        opening = result and result.opening or nil,
        gambit = result and result.gambit or nil,
        gambitPlayed = result and result.gambitPlayed or nil,
    }

    if not cancelled() and provider == "Claude 5" then
        EngineCore.rememberAnalysis(
            board,
            selectedSide,
            modeName,
            candidates,
            info
        )
    end

    return candidates, info
end

-- ----------------------------------------------------------------------------
-- Pondering + intelligent premove
-- ----------------------------------------------------------------------------
-- Premove safety check: runs when the opponent has moved and a premove was proposed.
-- Re-validates it in the NEW position: still legal? and how much does it cost compared with the best move?
function EngineCore.revalidatePremove(uci, board, side, report)
    if not uci or not report then
        return
    end
    task.spawn(function()
        local started = os.clock()
        while Claude1.isRunning() do
            if os.clock() - started > 1.5 then
                return
            end
            task.wait()
        end
        local fen = EngineCore.boardToFen(board, side)
        local legal = Claude1.legalMoves(fen)
        if not legal then
            report("Premove " .. uci .. " cancelled: the position changed and is not valid for you to move.", THEME.warning)
            return
        end
        local isLegal = false
        for _, move in ipairs(legal) do
            if move == uci then
                isLegal = true
                break
            end
        end
        if not isLegal then
            report("Premove " .. uci .. " CANCELLED: it is no longer legal after the opponent's move.", THEME.danger)
            return
        end
        local common = { fen = fen, timeLimit = 0.6, softLimit = 0.3, minDepth = 4, multiPV = 1, useBook = false,
            style = "Normal", qchecks = true, singular = false, yield = task.wait, yieldMin = 0.01, yieldMax = 0.02 }
        local best = Claude1.search(common)
        if not best or not best.lines or not best.lines[1] then
            return
        end
        local mine
        if best.lines[1].uci == uci then
            mine = best.lines[1]
        else
            common.onlyMoves = { [uci] = true }
            local forced = Claude1.search(common)
            mine = forced and forced.lines and forced.lines[1]
        end
        if not mine then
            return
        end
        local loss = best.lines[1].score - mine.score
        if math.abs(best.lines[1].score) > 29000 and math.abs(mine.score) < 29000 then
            loss = 9999
        end
        if loss <= 40 then
            report(string.format("Premove %s is still SAFE (%.2f from the best move).", uci, loss / 100), THEME.success)
        elseif loss <= 120 then
            report(string.format("Premove %s: CAUTION - %.2f worse than %s. Consider the new best move.", uci, loss / 100, best.lines[1].uci), THEME.warning)
        else
            report(string.format("Premove %s is UNSAFE (%.2f worse) - play %s instead.", uci, loss / 100, best.lines[1].uci), THEME.danger)
        end
    end)
end

function EngineCore.clearPremove()
    local pm = EngineCore.premove
    if pm.move then
        pm.move, pm.uci = nil, nil
        if EngineCore.refreshPremoveArrow then
            pcall(EngineCore.refreshPremoveArrow)
        end
        pm.tableData = nil
    end
end

function EngineCore.cancelPonder(clearArrow)
    EngineCore.ponderGeneration = EngineCore.ponderGeneration + 1
    EngineCore.ponderPositionKey = nil
    if clearArrow ~= false then
        EngineCore.clearPremove()
    end
end

-- pseudo move (only squares) used to draw the premove arrow
function EngineCore.uciToArrowMove(uci)
    return {
        fromFile = string.byte(string.sub(uci, 1, 1)) - 96,
        fromRank = tonumber(string.sub(uci, 2, 2)),
        toFile = string.byte(string.sub(uci, 3, 3)) - 96,
        toRank = tonumber(string.sub(uci, 4, 4)),
    }
end

-- The opponent is to move. Predict their likely replies, find our best answer to each,
-- and premove the move that is (near-)best against most of them. Deepens until cancelled.
function EngineCore.ponderOpponentTurn(generation, tableData, board, side, modeName)
    local function alive()
        return generation == EngineCore.ponderGeneration and EngineCore.ponderEnabled
    end
    local function cancelled()
        return not alive()
    end

    local opponent = opposite(side)
    local fenP1 = EngineCore.boardToFen(board, opponent)
    local style = EngineCore.enginePreference
    local rounds = { { 0.40, 0.22 }, { 1.0, 0.55 }, { 2.2, 1.3 }, { 4.5, 3.0 }, { 9.0, 6.0 } }

    -- premove state kept across rounds: evidence is smoothed and a shown premove is only changed
    -- when another move is clearly better for two rounds in a row (or the premove stops being sound)
    local smooth, committed, committedMiss, challenger, challengerRounds = {}, nil, 0, nil, 0

    for _, round in ipairs(rounds) do
        if not alive() then return end

        -- 1) the opponent's plausible replies (modelled with a neutral style)
        local oppResult = EngineCore.claudeSearch(board, opponent, {
            fen = fenP1,
            timeLimit = round[1], softLimit = round[2],
            multiPV = 4, style = "Normal", useBook = false,
            easyMinDepth = 0, qchecks = false, singular = false,
            cancelCheck = cancelled,
            yieldMin = EngineCore.PONDER_YIELD_MIN, yieldMax = EngineCore.PONDER_YIELD_MAX,
        })
        if not alive() then return end
        if not oppResult or not oppResult.lines or #oppResult.lines == 0 then
            return
        end

        local bestScore = oppResult.lines[1].score
        local replies, totalWeight = {}, 0
        for _, line in ipairs(oppResult.lines) do
            if line.score >= bestScore - 150 then
                local weight = math.exp((line.score - bestScore) / 70)
                table.insert(replies, { uci = line.uci, weight = weight })
                totalWeight = totalWeight + weight
            end
        end
        for _, reply in ipairs(replies) do
            reply.weight = reply.weight / totalWeight
        end

        -- 2) our best answers to each reply (also stored as pondered analyses)
        local analysed = {}
        local covered = 0
        for index, reply in ipairs(replies) do
            if index > 3 or not alive() then break end
            local fenC = Claude1.applyMove(fenP1, reply.uci)
            if fenC then
                local result = EngineCore.claudeSearch(nil, side, {
                    fen = fenC,
                    timeLimit = round[1] * 0.8, softLimit = round[2] * 0.7,
                    multiPV = TOP_MOVE_COUNT, style = style, useBook = false,
                    easyMinDepth = 0, qchecks = true, singular = false,
                    cancelCheck = cancelled,
                    yieldMin = EngineCore.PONDER_YIELD_MIN, yieldMax = EngineCore.PONDER_YIELD_MAX,
                })
                if not alive() then return end
                if result and result.lines and #result.lines > 0 then
                    table.insert(analysed, { reply = reply, lines = result.lines })
                    covered = covered + reply.weight

                    -- store the full analysis so the answer is instant if this reply is played
                    local replyMove = EngineCore.findLegalMoveByUci(board, opponent, reply.uci)
                    if replyMove then
                        local boardC = replyMove._nextBoard or applyMove(board, replyMove)
                        local candidates = EngineCore.claudeLinesToCandidates(boardC, side, result.lines)
                        if #candidates > 0 then
                            EngineCore.storePonderPlan(boardC, side, modeName, candidates, result.depth, result.opening, result.gambit)
                        end
                    end
                end
            end
        end
        if not alive() then return end

        -- 3) choose the premove: how often is each move (near-)best against the analysed replies?
        if #analysed > 0 then
            local cover = {}
            for _, entry in ipairs(analysed) do
                local top = entry.lines[1].score
                for _, line in ipairs(entry.lines) do
                    if line.score >= top - 30 then
                        cover[line.uci] = (cover[line.uci] or 0) + entry.reply.weight
                    end
                end
            end
            if covered > 0 then
                for uci, weight in pairs(cover) do
                    cover[uci] = weight / covered
                end
            end
            -- smooth across rounds so one noisy round cannot flip the recommendation
            for uci, value in pairs(cover) do
                smooth[uci] = smooth[uci] and (0.5 * smooth[uci] + 0.5 * value) or value
            end
            for uci, value in pairs(smooth) do
                if cover[uci] == nil then
                    smooth[uci] = value * 0.5
                end
            end

            local bestUci, bestValue = nil, 0
            for uci, value in pairs(smooth) do
                if value > bestValue then
                    bestUci, bestValue = uci, value
                end
            end
            local strong = bestUci ~= nil and covered >= 0.70 and bestValue >= 0.75

            local pm = EngineCore.premove
            local previous = pm.uci
            if committed then
                local current = smooth[committed] or 0
                if current >= 0.55 and covered >= 0.55 then
                    committedMiss = 0
                    if strong and current < 0.70 and bestUci ~= committed and bestValue >= current + 0.25 then
                        if challenger == bestUci then
                            challengerRounds = challengerRounds + 1
                        else
                            challenger, challengerRounds = bestUci, 1
                        end
                        if challengerRounds >= 2 then
                            committed, challenger, challengerRounds = bestUci, nil, 0
                        end
                    else
                        challenger, challengerRounds = nil, 0
                    end
                else
                    committedMiss = committedMiss + 1
                    if committedMiss >= 2 then
                        committed = nil -- only dropped after two unsound rounds in a row
                    end
                end
            end
            if not committed and strong then
                committed, committedMiss, challenger, challengerRounds = bestUci, 0, nil, 0
            end

            if committed then
                local arrowMove = EngineCore.uciToArrowMove(committed)
                local piece = board[arrowMove.fromRank] and board[arrowMove.fromRank][arrowMove.fromFile]
                if piece and piece.color == side then
                    pm.move, pm.uci, pm.tableData = arrowMove, committed, tableData
                else
                    committed = nil
                end
            end
            if not committed then
                pm.move, pm.uci = nil, nil
            end
            if pm.uci ~= previous and EngineCore.refreshPremoveArrow then
                pcall(EngineCore.refreshPremoveArrow)
            end
        end
        task.wait(0.05)
    end
end

-- Called by the scan loop whenever the opponent is to move on a stable board.
function EngineCore.onOpponentTurn(tableData, board, positionKey, side, modeName)
    if not EngineCore.ponderEnabled or EngineCore.ponderPositionKey == positionKey then
        return
    end
    EngineCore.cancelPonder(false)
    EngineCore.ponderPositionKey = positionKey
    local generation = EngineCore.ponderGeneration
    task.spawn(function()
        local ok, err = pcall(EngineCore.ponderOpponentTurn, generation, tableData, board, side, modeName)
        if not ok then
            warn("[Claude 5] ponder error: " .. tostring(err))
        end
    end)
end

-- Predicted-line pondering: after we show our move, keep thinking about the position
-- that arises if the opponent plays the reply we expect.
function EngineCore.ponderPredicted(generation, board, best, side, modeName)
    local function alive()
        return generation == EngineCore.ponderGeneration and EngineCore.ponderEnabled
    end
    local function cancelled()
        return not alive()
    end

    local fenA = EngineCore.boardToFen(board, side)
    local fenB = Claude1.applyMove(fenA, moveToCoordinates(best.move))
    local fenC = fenB and Claude1.applyMove(fenB, moveToCoordinates(best.reply))
    if not fenC then
        return
    end
    local nextBoard = best.move._nextBoard or applyMove(board, best.move)
    local boardC = best.reply._nextBoard or applyMove(nextBoard, best.reply)
    local style = EngineCore.enginePreference

    for _, round in ipairs({ { 1.2, 0.7 }, { 3.0, 2.0 }, { 7.0, 5.0 }, { 14.0, 10.0 } }) do
        if not alive() then return end
        local result = EngineCore.claudeSearch(nil, side, {
            fen = fenC,
            timeLimit = round[1], softLimit = round[2],
            multiPV = TOP_MOVE_COUNT, style = style, useBook = false,
            easyMinDepth = 0, qchecks = true, singular = true,
            cancelCheck = cancelled,
            yieldMin = EngineCore.PONDER_YIELD_MIN, yieldMax = EngineCore.PONDER_YIELD_MAX,
        })
        if not alive() then return end
        if result and result.lines and #result.lines > 0 and not result.cancelled then
            local candidates = EngineCore.claudeLinesToCandidates(boardC, side, result.lines)
            if #candidates > 0 then
                EngineCore.storePonderPlan(boardC, side, modeName, candidates, result.depth, result.opening, result.gambit)
            end
        end
        task.wait(0.05)
    end
end

function EngineCore.afterFinalDisplay(board, tableData, candidates, searchInfo, side, modeName)
    if not EngineCore.ponderEnabled then
        return
    end
    local best = candidates and candidates[1]
    if not best or not best.reply or not best.move then
        return
    end
    EngineCore.cancelPonder(false)
    local generation = EngineCore.ponderGeneration
    task.spawn(function()
        local ok, err = pcall(EngineCore.ponderPredicted, generation, board, best, side, modeName)
        if not ok then
            warn("[Claude 5] ponder error: " .. tostring(err))
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Game recorder: every analysis (and every input problem) is logged so a lost game can be
-- replayed move by move. "COPY GAME LOG" in Settings puts the log on the clipboard.
-- ----------------------------------------------------------------------------
EngineCore.gameLog = {}
EngineCore.gameLogCount = 0

function EngineCore.logEvent(text)
    table.insert(EngineCore.gameLog, string.format("[%s] %s", os.date("%H:%M:%S"), text))
    while #EngineCore.gameLog > 600 do
        table.remove(EngineCore.gameLog, 1)
    end
end

local function logScore(score, side)
    local own = side == "white" and score or -score
    if math.abs(own) >= MATE_SCORE - 1000 then
        local plies = MATE_SCORE - math.abs(own)
        return (own > 0 and "#" or "-#") .. tostring(math.ceil(plies / 2))
    end
    return string.format("%+.2f", own / 100)
end

function EngineCore.recordAnalysis(board, side, candidates, info, modeName)
    if not candidates or not candidates[1] then
        return
    end
    EngineCore.gameLogCount = EngineCore.gameLogCount + 1
    local clock = side == "white" and BoardTracker.lastWhiteClock or BoardTracker.lastBlackClock
    local alternatives = {}
    for index = 2, #candidates do
        table.insert(alternatives, moveToCoordinates(candidates[index].move) .. "(" .. logScore(candidates[index].score, side) .. ")")
    end
    EngineCore.logEvent(string.format(
        "#%d %s mode=%s style=%s src=%s depth=%s nodes=%s time=%.2fs clock=%s | best %s (%s) | alt %s | opening=%s%s | fen %s",
        EngineCore.gameLogCount, side, tostring(modeName), tostring(EngineCore.enginePreference),
        tostring(info and info.provider or "?"), tostring(info and info.depth or "?"),
        tostring(info and info.nodes or "?"), tonumber(info and info.elapsed) or 0,
        type(clock) == "number" and string.format("%.0fs", clock) or "?",
        moveToCoordinates(candidates[1].move), logScore(candidates[1].score, side),
        #alternatives > 0 and table.concat(alternatives, " ") or "-",
        tostring(info and info.opening or "-"),
        info and info.gambit and (" gambit=" .. info.gambit.name) or "",
        EngineCore.boardToFen(board, side)
    ))
end

function EngineCore.copyGameLog()
    if #EngineCore.gameLog == 0 then
        return false, 0
    end
    local text = "Claude 5 game log\n" .. table.concat(EngineCore.gameLog, "\n")
    local copied = MobileSupport.tryCopyText(text)
    return copied and true or false, #EngineCore.gameLog
end
local function pieceMatches(board, square, color, kind) local file, rank
= squareCoordinates(square) if not file then return false end

    local piece = board[rank][file]
    return piece and piece.color == color and piece.kind == kind

end

local function detectOpening(board, sideToMove) local bookDescription =
OpeningBook.describePosition(board, sideToMove) if bookDescription then
return bookDescription end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "c5", "black", "pawn") then
        return "Sicilian Defense"
    end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "e6", "black", "pawn") then
        return "French Defense"
    end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "c6", "black", "pawn") then
        return "Caro-Kann Defense"
    end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "d5", "black", "pawn") then
        return "Scandinavian Defense"
    end

    if pieceMatches(board, "d4", "white", "pawn")
        and pieceMatches(board, "d5", "black", "pawn")
        and pieceMatches(board, "c4", "white", "pawn") then
        return "Queen's Gambit"
    end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "e5", "black", "pawn")
        and pieceMatches(board, "f3", "white", "knight")
        and pieceMatches(board, "c6", "black", "knight")
        and pieceMatches(board, "b5", "white", "bishop") then
        return "Ruy Lopez"
    end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "e5", "black", "pawn")
        and pieceMatches(board, "f3", "white", "knight")
        and pieceMatches(board, "c6", "black", "knight")
        and pieceMatches(board, "c4", "white", "bishop") then
        return "Italian Game"
    end

    if pieceMatches(board, "d4", "white", "pawn")
        and pieceMatches(board, "f3", "white", "knight")
        and pieceMatches(board, "f4", "white", "bishop") then
        return "London System"
    end

    if pieceMatches(board, "d4", "white", "pawn")
        and pieceMatches(board, "c4", "white", "pawn")
        and pieceMatches(board, "f6", "black", "knight")
        and pieceMatches(board, "g6", "black", "pawn") then
        return "King's Indian Defense"
    end

    if pieceMatches(board, "e4", "white", "pawn")
        and pieceMatches(board, "e5", "black", "pawn") then
        return "King's Pawn Game"
    end

    if pieceMatches(board, "d4", "white", "pawn")
        and pieceMatches(board, "d5", "black", "pawn") then
        return "Queen's Pawn Game"
    end

    return "Custom / Middlegame Position"

end

local function pieceDescription(piece, file, rank) return
string.upper(piece.kind) .. " on " .. string.upper(squareName(file,
rank)) end

local function scanThreats(board, selectedSide) local enemy =
opposite(selectedSide) local attacked = {} local hanging = {} local
targets = {}

    for rank = 1, 8 do
        for file = 1, 8 do
            local piece = board[rank][file]
            if piece then
                if piece.color == selectedSide then
                    local underAttack = isSquareAttacked(board, file, rank, enemy)
                    if underAttack then
                        table.insert(attacked, {
                            value = PIECE_VALUES[piece.kind],
                            text = pieceDescription(piece, file, rank),
                        })

                        local defended = isSquareAttacked(board, file, rank, selectedSide)
                        if not defended then
                            table.insert(hanging, {
                                value = PIECE_VALUES[piece.kind],
                                text = pieceDescription(piece, file, rank),
                            })
                        end
                    end
                elseif isSquareAttacked(board, file, rank, selectedSide) then
                    table.insert(targets, {
                        value = PIECE_VALUES[piece.kind],
                        text = pieceDescription(piece, file, rank),
                    })
                end
            end
        end
    end

    local function sortByValue(list)
        table.sort(list, function(first, second)
            return first.value > second.value
        end)
    end

    sortByValue(attacked)
    sortByValue(hanging)
    sortByValue(targets)

    local bestCapture = nil
    local bestCaptureGain = -math.huge

    for _, move in ipairs(generateLegalMoves(board, selectedSide)) do
        if move.capture then
            local gain = (PIECE_VALUES[move.capture.kind] or 0)
                - (PIECE_VALUES[move.piece.kind] or 0) * 0.18

            if gain > bestCaptureGain then
                bestCaptureGain = gain
                bestCapture = move
            end
        end
    end

    return {
        inCheck = isKingInCheck(board, selectedSide),
        attacked = attacked,
        hanging = hanging,
        targets = targets,
        bestCapture = bestCapture,
    }

end

local function summarizeThreatList(list, emptyText) if #list == 0 then
return emptyText end

    local lines = {}
    for index = 1, math.min(4, #list) do
        table.insert(lines, "• " .. list[index].text)
    end

    if #list > 4 then
        table.insert(lines, "+ " .. tostring(#list - 4) .. " more")
    end

    return table.concat(lines, "\n")

end

local sourceHighlight = nil local destinationHighlight = nil local
sourcePulse = nil local destinationPulse = nil local arrowStart = nil
local arrowEnd = nil local arrowBeam = nil local board2DEffects = {
source = nil, destination = nil, sourcePulse = nil, destinationPulse =
nil, }

local highlightsEnabled = true local arrowEnabled = true

local function createHighlightPart(name, color) local part =
Instance.new("Part") part.Name = name part.Anchored = true
part.CanCollide = false part.CanTouch = false part.CanQuery = false
part.CastShadow = false part.Material = Enum.Material.Neon part.Color =
color part.Transparency = 1 part.Size = Vector3.new(1, 0.07, 1)
part.Parent = Workspace return part end

local function createArrowNode(name) local part = Instance.new("Part")
part.Name = name part.Anchored = true part.CanCollide = false
part.CanTouch = false part.CanQuery = false part.Transparency = 1
part.Size = Vector3.new(0.1, 0.1, 0.1) part.Parent = Workspace

    local attachment = Instance.new("Attachment")
    attachment.Name = "ArrowAttachment"
    attachment.Parent = part

    return part, attachment

end

local function ensureBoardEffects() if not sourceHighlight or not
sourceHighlight.Parent then sourceHighlight = createHighlightPart(
"TwitchysHub_SourceHighlight", THEME.source ) end

    if not destinationHighlight or not destinationHighlight.Parent then
        destinationHighlight = createHighlightPart(
            "TwitchysHub_DestinationHighlight",
            THEME.destination
        )
    end

    if not arrowStart or not arrowStart.Parent then
        local startAttachment
        arrowStart, startAttachment = createArrowNode("TwitchysHub_ArrowStart")

        local endAttachment
        arrowEnd, endAttachment = createArrowNode("TwitchysHub_ArrowEnd")

        arrowBeam = Instance.new("Beam")
        arrowBeam.Name = "MoveArrow"
        arrowBeam.Attachment0 = startAttachment
        arrowBeam.Attachment1 = endAttachment
        arrowBeam.FaceCamera = true
        arrowBeam.Width0 = 0.22
        arrowBeam.Width1 = 0.10
        arrowBeam.LightEmission = 1
        arrowBeam.LightInfluence = 0
        arrowBeam.Color = ColorSequence.new(THEME.accent2, THEME.destination)
        arrowBeam.Transparency = NumberSequence.new(0.12)
        arrowBeam.Enabled = false
        arrowBeam.Parent = arrowStart
    end

end

local function stopEffectTweens() if sourcePulse then
sourcePulse:Cancel() sourcePulse = nil end if destinationPulse then
destinationPulse:Cancel() destinationPulse = nil end if
board2DEffects.sourcePulse then board2DEffects.sourcePulse:Cancel()
board2DEffects.sourcePulse = nil end if board2DEffects.destinationPulse
then board2DEffects.destinationPulse:Cancel()
board2DEffects.destinationPulse = nil end end

local function clear2DBoardEffects() for _, key in ipairs({ "source",
"destination" }) do local overlay = board2DEffects[key] if overlay then
overlay:Destroy() board2DEffects[key] = nil end end end

local function find2DBoardSquare(name) local boardGui =
PlayerGui:FindFirstChild("2DBoard") if not boardGui then return nil end

    local square = boardGui:FindFirstChild(string.lower(name), true)
    if square and square:IsA("GuiObject") then
        return square
    end

    return nil

end

local function create2DBoardHighlight(square, name, color, transparency)
if not square then return nil end

    local overlay = Instance.new("Frame")
    overlay.Name = name
    overlay.BackgroundColor3 = color
    overlay.BackgroundTransparency = transparency
    overlay.BorderSizePixel = 0
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.ZIndex = math.max(50, square.ZIndex + 20)
    overlay.Parent = square

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Transparency = 0.08
    stroke.Thickness = 3
    stroke.Parent = overlay

    return overlay

end

local function show2DBoardEffects(fromSquare, toSquare)
clear2DBoardEffects()

    if not highlightsEnabled then
        return
    end

    local sourceSquare = find2DBoardSquare(fromSquare)
    local destinationSquare = find2DBoardSquare(toSquare)

    board2DEffects.source = create2DBoardHighlight(
        sourceSquare,
        "TwitchysHub_2DSourceHighlight",
        THEME.source,
        0.48
    )
    board2DEffects.destination = create2DBoardHighlight(
        destinationSquare,
        "TwitchysHub_2DDestinationHighlight",
        THEME.destination,
        0.40
    )

    if board2DEffects.source then
        board2DEffects.sourcePulse = TweenService:Create(
            board2DEffects.source,
            TweenInfo.new(0.68, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            { BackgroundTransparency = 0.67 }
        )
        board2DEffects.sourcePulse:Play()
    end

    if board2DEffects.destination then
        board2DEffects.destinationPulse = TweenService:Create(
            board2DEffects.destination,
            TweenInfo.new(0.58, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            { BackgroundTransparency = 0.61 }
        )
        board2DEffects.destinationPulse:Play()
    end

end

local function hideBoardEffects() stopEffectTweens()
clear2DBoardEffects() EngineCore.hideRankedMoveArrows()

    if sourceHighlight then
        sourceHighlight.Transparency = 1
    end
    if destinationHighlight then
        destinationHighlight.Transparency = 1
    end
    if arrowBeam then
        arrowBeam.Enabled = false
    end

end

local function positionHighlight(highlight, squareEntry) if not
highlight or not squareEntry then return false end

    local part = squareEntry.visualPart or getVisualPart(squareEntry.object)
    if not part then
        return false
    end

    highlight.Size = Vector3.new(
        math.max(part.Size.X * 0.91, 0.2),
        0.075,
        math.max(part.Size.Z * 0.91, 0.2)
    )

    highlight.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.05, 0)
    return true

end

local function squareTopPosition(squareEntry) if not squareEntry then
return nil end

    local part = squareEntry.visualPart or getVisualPart(squareEntry.object)
    if not part then
        return squareEntry.position + Vector3.new(0, 0.35, 0)
    end

    return (part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.26, 0)).Position

end

function EngineCore.ensureRankedArrowObjects() for index = 1,
TOP_MOVE_COUNT + 1 do local entry = EngineCore.rankedArrows[index] if not
entry or not entry.start or not entry.start.Parent or not entry.finish
or not entry.finish.Parent or not entry.beam or not entry.beam.Parent
then

            local startPart, startAttachment = createArrowNode(
                "TwitchysHub_RankedArrowStart" .. tostring(index)
            )
            local endPart, endAttachment = createArrowNode(
                "TwitchysHub_RankedArrowEnd" .. tostring(index)
            )

            local beam = Instance.new("Beam")
            beam.Name = "RankedMoveArrow" .. tostring(index)
            beam.Attachment0 = startAttachment
            beam.Attachment1 = endAttachment
            beam.FaceCamera = true
            beam.Width0 = index == 1 and 0.26 or (index == 2 and 0.20 or 0.16)
            beam.Width1 = index == 1 and 0.12 or (index == 2 and 0.09 or 0.07)
            beam.LightEmission = 1
            beam.LightInfluence = 0
            beam.Transparency = NumberSequence.new(index == 1 and 0.06 or 0.18)
            beam.Enabled = false
            beam.Parent = startPart

            EngineCore.rankedArrows[index] = {
                start = startPart,
                finish = endPart,
                beam = beam,
            }
        end
    end

    local overlay = PlayerGui:FindFirstChild("TwitchysHub_Ranked2DArrows")
    if not overlay then
        overlay = Instance.new("ScreenGui")
        overlay.Name = "TwitchysHub_Ranked2DArrows"
        overlay.ResetOnSpawn = false
        overlay.IgnoreGuiInset = false
        overlay.DisplayOrder = 1490
        overlay.ZIndexBehavior = Enum.ZIndexBehavior.Global
        overlay.Parent = PlayerGui
    end
    overlay.Enabled = EngineCore.windowFocused ~= false
    EngineCore.ranked2DOverlay = overlay

end

function EngineCore.clearRanked2DOverlay() local overlay =
EngineCore.ranked2DOverlay or
PlayerGui:FindFirstChild("TwitchysHub_Ranked2DArrows") if overlay then
overlay:ClearAllChildren() end end

function EngineCore.hideRankedMoveArrows() for _, entry in
ipairs(EngineCore.rankedArrows) do if entry.beam then entry.beam.Enabled
= false end end

    EngineCore.clearRanked2DOverlay()

end

function EngineCore.isGuiObjectVisibleOnScreen(object) if
EngineCore.windowFocused == false or (EngineCore.suspend2DArrowsUntil
and os.clock() < EngineCore.suspend2DArrowsUntil) then return false end

    if not object or not object:IsA("GuiObject") then
        return false
    end

    local current = object
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("LayerCollector") and not current.Enabled then
            return false
        end
        current = current.Parent
    end

    local size = object.AbsoluteSize
    local position = object.AbsolutePosition
    if size.X <= 1 or size.Y <= 1 then
        return false
    end

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize
    if viewport then
        if position.X + size.X <= 0
            or position.Y + size.Y <= 0
            or position.X >= viewport.X
            or position.Y >= viewport.Y then
            return false
        end
    end

    return true

end

EngineCore.PREMOVE_COLOR = Color3.fromRGB(236, 64, 56)

-- Validates both squares and returns screen geometry for a 2D arrow, or nil.
function EngineCore.arrowGeometry(fromSquare, toSquare)
    if not EngineCore.ranked2DOverlay or not fromSquare or not toSquare then
        return nil
    end

    -- The 2D chessboard stays in PlayerGui while hidden during normal 3D play and can keep stale
    -- AbsolutePosition values. Draw only when both squares and every ancestor are really visible.
    if not EngineCore.isGuiObjectVisibleOnScreen(fromSquare)
        or not EngineCore.isGuiObjectVisibleOnScreen(toSquare) then
        return nil
    end

    local fromSize = fromSquare.AbsoluteSize
    local toSize = toSquare.AbsoluteSize
    local smallest = math.min(fromSize.X, fromSize.Y, toSize.X, toSize.Y)
    local largest = math.max(fromSize.X, fromSize.Y, toSize.X, toSize.Y)

    -- transient mixed geometry after alt-tab / resize would draw a huge diagonal: reject it
    if smallest <= 1 or largest / smallest > 1.35 then
        return nil
    end

    local startPosition = fromSquare.AbsolutePosition + fromSize / 2
    local endPosition = toSquare.AbsolutePosition + toSize / 2
    local delta = endPosition - startPosition
    local length = delta.Magnitude
    if length < 8 then
        return nil
    end

    local averageSquareSize = (fromSize.X + fromSize.Y + toSize.X + toSize.Y) / 4
    local fromFile, fromRank = squareCoordinates(fromSquare.Name)
    local toFile, toRank = squareCoordinates(toSquare.Name)
    if fromFile and toFile then
        local gridDistance = math.sqrt(
            (toFile - fromFile) * (toFile - fromFile) + (toRank - fromRank) * (toRank - fromRank)
        )
        local expectedLength = gridDistance * averageSquareSize
        if expectedLength > 0 and (length < expectedLength * 0.58 or length > expectedLength * 1.55) then
            return nil
        end
    end

    return startPosition, endPosition, delta, length, math.deg(math.atan2(delta.Y, delta.X)), averageSquareSize
end

local function arrowFrame(parent, name, center, width, height, angle, color, transparency, zIndex)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromOffset(center.X, center.Y)
    frame.Size = UDim2.fromOffset(width, height)
    frame.Rotation = angle or 0
    frame.BackgroundColor3 = color
    frame.BackgroundTransparency = transparency
    frame.BorderSizePixel = 0
    frame.ZIndex = zIndex
    frame.Parent = parent
    return frame
end

local function roundFrame(frame, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius or UDim.new(1, 0)
    corner.Parent = frame
    return corner
end

-- index 1..3 = ranked best / second / third, index 4 = premove (dashed red)
function EngineCore.create2DRankedArrow(index, fromSquare, toSquare, color)
    local startPosition, endPosition, delta, length, angle, square = EngineCore.arrowGeometry(fromSquare, toSquare)
    if not startPosition then
        return
    end

    local overlay = EngineCore.ranked2DOverlay
    local premove = index == 4
    local direction = delta / length
    local weights = { 0.17, 0.135, 0.11, 0.12 }
    local thickness = math.max(5, square * weights[index])
    local headSize = thickness * 3.0
    local z = 80 + index * 8

    local tailPosition = startPosition + direction * (square * 0.22)
    local tipPosition = endPosition - direction * (square * 0.05)
    local shaftEnd = tipPosition - direction * (headSize * 0.62)
    local shaftLength = math.max(6, (shaftEnd - tailPosition).Magnitude)
    local shaftCenter = (tailPosition + shaftEnd) / 2

    -- soft landing disc on the destination square (best move and premove only)
    if index == 1 or premove then
        local disc = arrowFrame(overlay, "ArrowTarget" .. index, endPosition, square * 0.80, square * 0.80, 0, color, 0.80, z - 3)
        roundFrame(disc)
        if premove then
            disc.BackgroundTransparency = 1
            local ring = Instance.new("UIStroke")
            ring.Color = color
            ring.Thickness = 2.5
            ring.Transparency = 0.15
            ring.Parent = disc
        end
    end

    -- drop shadow
    local shadow = arrowFrame(overlay, "ArrowShadow" .. index, shaftCenter + Vector2.new(0, 2), shaftLength + 4, thickness + 5, angle, Color3.new(0, 0, 0), 0.78, z - 2)
    roundFrame(shadow)

    if premove then
        -- dashed shaft: clearly different from the solid engine arrows
        local dash = thickness * 2.6
        local gap = thickness * 1.5
        local count = math.max(1, math.floor((shaftLength + gap) / (dash + gap)))
        local used = count * dash + (count - 1) * gap
        local first = tailPosition + direction * ((shaftLength - used) / 2)
        for step = 0, count - 1 do
            local center = first + direction * (step * (dash + gap) + dash / 2)
            local piece = arrowFrame(overlay, "ArrowDash" .. step, center, dash, thickness, angle, color, 0.04, z)
            roundFrame(piece)
        end
    else
        local shaft = arrowFrame(overlay, "ArrowShaft" .. index, shaftCenter, shaftLength, thickness, angle, color, index == 1 and 0.02 or 0.14, z)
        roundFrame(shaft)
        local gradient = Instance.new("UIGradient")
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.55),
            NumberSequenceKeypoint.new(0.55, 0.10),
            NumberSequenceKeypoint.new(1, 0),
        })
        gradient.Parent = shaft
        local outline = Instance.new("UIStroke")
        outline.Color = Color3.new(0, 0, 0)
        outline.Thickness = 1
        outline.Transparency = 0.65
        outline.Parent = shaft
    end

    -- arrow head (with its own shadow)
    local headCenter = tipPosition - direction * (headSize * 0.42)
    for pass = 1, 2 do
        local head = Instance.new("TextLabel")
        head.Name = "ArrowHead" .. index .. "_" .. pass
        head.AnchorPoint = Vector2.new(0.5, 0.5)
        head.Position = UDim2.fromOffset(headCenter.X + (pass == 1 and 2 or 0), headCenter.Y + (pass == 1 and 2 or 0))
        head.Size = UDim2.fromOffset(headSize, headSize)
        head.BackgroundTransparency = 1
        head.Font = Enum.Font.GothamBold
        head.Text = "▶"
        head.TextColor3 = pass == 1 and Color3.new(0, 0, 0) or color
        head.TextTransparency = pass == 1 and 0.72 or 0
        head.TextSize = math.max(18, headSize * 1.25)
        head.Rotation = angle
        head.ZIndex = z + pass
        head.Parent = overlay
    end

    -- origin ring
    local ring = arrowFrame(overlay, "ArrowOrigin" .. index, startPosition, square * 0.34, square * 0.34, 0, color, 1, z + 1)
    roundFrame(ring)
    local ringStroke = Instance.new("UIStroke")
    ringStroke.Color = color
    ringStroke.Thickness = 2.5
    ringStroke.Transparency = 0.12
    ringStroke.Parent = ring

    if premove then
        local pill = arrowFrame(overlay, "ArrowPremoveTag", endPosition + Vector2.new(0, -square * 0.50), math.max(54, square * 1.2), 16, 0, color, 0.05, z + 4)
        roundFrame(pill)
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.Text = "PREMOVE"
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextSize = 9
        label.ZIndex = z + 5
        label.Parent = pill
    else
        local badge = arrowFrame(overlay, "ArrowBadge" .. index, endPosition + Vector2.new(square * 0.27, -square * 0.27), square * 0.30, square * 0.30, 0, color, 0.04, z + 4)
        roundFrame(badge)
        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color = Color3.new(0, 0, 0)
        badgeStroke.Thickness = 1
        badgeStroke.Transparency = 0.55
        badgeStroke.Parent = badge
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.Text = tostring(index)
        label.TextColor3 = Color3.new(0.06, 0.06, 0.08)
        label.TextSize = math.max(10, square * 0.20)
        label.ZIndex = z + 5
        label.Parent = badge
    end
end

-- red dashed premove arrow (only while Pondering + Premove are on and a premove is proposed)
function EngineCore.drawPremoveArrow(tableData)
    local pm = EngineCore.premove
    if not (EngineCore.premoveEnabled and EngineCore.ponderEnabled and pm and pm.move) then
        return
    end

    local move = pm.move
    local fromName = squareName(move.fromFile, move.fromRank)
    local toName = squareName(move.toFile, move.toRank)

    local entry = EngineCore.rankedArrows[4]
    if entry and tableData.squares then
        local startPosition = squareTopPosition(tableData.squares[fromName])
        local endPosition = squareTopPosition(tableData.squares[toName])
        if startPosition and endPosition then
            entry.start.Position = startPosition
            entry.finish.Position = endPosition
            entry.beam.Color = ColorSequence.new(EngineCore.PREMOVE_COLOR)
            entry.beam.Enabled = true
        end
    end

    EngineCore.create2DRankedArrow(
        4,
        find2DBoardSquare(fromName),
        find2DBoardSquare(toName),
        EngineCore.PREMOVE_COLOR
    )
end


-- opening / gambit tag shown directly above the piece that makes the key move (2D boards)
function EngineCore.drawOpeningTag(tableData)
    local tag = EngineCore.openingTag
    local overlay = EngineCore.ranked2DOverlay
    if not tag or not tag.uci or not overlay then
        return
    end
    local square = find2DBoardSquare(string.sub(tag.uci, 1, 2))
    if not square or not EngineCore.isGuiObjectVisibleOnScreen(square) then
        return
    end
    local size = square.AbsoluteSize
    local center = square.AbsolutePosition + size / 2
    local color = tag.warm and Color3.fromRGB(217, 119, 87) or Color3.fromRGB(122, 162, 247)
    local width = math.max(84, #tag.text * 6.4 + 16)
    local pill = arrowFrame(overlay, "OpeningTag", center + Vector2.new(0, -size.Y * 0.66), width, 18, 0, color, 0.06, 160)
    roundFrame(pill)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = pill
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.Text = tag.text
    label.TextColor3 = Color3.new(0.07, 0.06, 0.08)
    label.TextSize = 10
    label.ZIndex = 161
    label.Parent = pill
end

function EngineCore.showRankedMoveArrows(tableData, candidates)
    EngineCore.hideRankedMoveArrows()
    if not arrowEnabled or not tableData then
        return
    end

    EngineCore.ensureRankedArrowObjects()
    candidates = candidates or {}
    local colors = { THEME.success, THEME.accent2, THEME.warning }
    local multi = EngineCore.multiArrowEnabled and not EngineCore.bestMoveOnly
    local limit = multi and math.min(TOP_MOVE_COUNT, #candidates) or math.min(1, #candidates)

    for index = 1, limit do
        local candidate = candidates[index]
        local move = candidate and candidate.move
        local entry = EngineCore.rankedArrows[index]
        if move and entry then
            local fromName = squareName(move.fromFile, move.fromRank)
            local toName = squareName(move.toFile, move.toRank)
            local color = colors[index]

            -- 3D beams for ranked arrows (the single best-move beam is drawn by showMoveEffects)
            if multi then
                local startPosition = squareTopPosition(tableData.squares[fromName])
                local endPosition = squareTopPosition(tableData.squares[toName])
                if startPosition and endPosition then
                    entry.start.Position = startPosition
                    entry.finish.Position = endPosition
                    entry.beam.Color = ColorSequence.new(color)
                    entry.beam.Enabled = true
                end
            end

            EngineCore.create2DRankedArrow(
                index,
                find2DBoardSquare(fromName),
                find2DBoardSquare(toName),
                color
            )
        end
    end

    EngineCore.drawPremoveArrow(tableData)
    EngineCore.drawOpeningTag(tableData)
end
local function showMoveEffects(tableData, move) ensureBoardEffects()
stopEffectTweens()

    local fromSquare = squareName(move.fromFile, move.fromRank)
    local toSquare = squareName(move.toFile, move.toRank)
    local fromEntry = tableData.squares[fromSquare]
    local toEntry = tableData.squares[toSquare]

    show2DBoardEffects(fromSquare, toSquare)

    if highlightsEnabled then
        local sourceReady = positionHighlight(sourceHighlight, fromEntry)
        local destinationReady = positionHighlight(destinationHighlight, toEntry)

        if sourceReady then
            sourceHighlight.Transparency = 0.20
            sourcePulse = TweenService:Create(
                sourceHighlight,
                TweenInfo.new(0.68, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                { Transparency = 0.60 }
            )
            sourcePulse:Play()
        end

        if destinationReady then
            destinationHighlight.Transparency = 0.13
            destinationPulse = TweenService:Create(
                destinationHighlight,
                TweenInfo.new(0.58, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                { Transparency = 0.49 }
            )
            destinationPulse:Play()
        end
    else
        sourceHighlight.Transparency = 1
        destinationHighlight.Transparency = 1
    end

    if arrowEnabled and not EngineCore.multiArrowEnabled and fromEntry and toEntry then
        local startPosition = squareTopPosition(fromEntry)
        local endPosition = squareTopPosition(toEntry)

        if startPosition and endPosition then
            arrowStart.Position = startPosition
            arrowEnd.Position = endPosition
            arrowBeam.Enabled = true
        end
    elseif arrowBeam then
        arrowBeam.Enabled = false
    end

end

-- Must exist before helper methods are assigned below.
local MobileSupport = {
    BASE_MENU_WIDTH = 500,
    BASE_MENU_HEIGHT = 560,
    COLLAPSED_MENU_HEIGHT = 62,
    BASE_MENU_SCALE = 0.92,
    menuTargetScale = 0.92,
    expandedFrameHeight = 560,
    responsiveViewportConnection = nil,
}

function MobileSupport.tryCopyText(text) local environment = rawget(_G,
"TWITCHYS_ENV") if type(environment) == "table" and
type(environment.CopyText) == "function" then local succeeded, copied =
pcall(environment.CopyText, text) if succeeded and copied ~= false then
return true end end

    local globalEnvironment = _G
    local getEnvironment = rawget(_G, "getgenv")
    if type(getEnvironment) == "function" then
        local succeeded, result = pcall(getEnvironment)
        if succeeded and type(result) == "table" then
            globalEnvironment = result
        end
    end

    for _, name in ipairs({ "setclipboard", "toclipboard", "set_clipboard" }) do
        local copyFunction = rawget(globalEnvironment, name) or rawget(_G, name)
        if type(copyFunction) == "function" then
            local succeeded = pcall(copyFunction, text)
            if succeeded then
                return true
            end
        end
    end

    return false

end

local function addCorner(object, radius) local corner =
Instance.new("UICorner") corner.CornerRadius = UDim.new(0, radius)
corner.Parent = object return corner end

local function addStroke(object, color, transparency, thickness) local
stroke = Instance.new("UIStroke") stroke.Color = color
stroke.Transparency = transparency stroke.Thickness = thickness or 1
stroke.Parent = object return stroke end

local function createLabel(parent, name, text, position, size, textSize,
color, font) local label = Instance.new("TextLabel") label.Name = name
label.BackgroundTransparency = 1 label.Position = position label.Size =
size label.Font = font or Enum.Font.Gotham label.Text = text
label.TextSize = textSize label.TextColor3 = color label.TextXAlignment
= Enum.TextXAlignment.Left label.TextYAlignment =
Enum.TextYAlignment.Center label.Parent = parent return label end

local function createButton(parent, name, text, position, size,
backgroundColor) local button = Instance.new("TextButton") button.Name =
name button.Position = position button.Size = size
button.BackgroundColor3 = backgroundColor button.BorderSizePixel = 0
button.AutoButtonColor = false button.Font = Enum.Font.GothamBold
button.Text = text button.TextSize = 12 button.TextColor3 = THEME.text
button.Parent = parent

    addCorner(button, 10)
    addStroke(button, Color3.new(1, 1, 1), 0.88, 1)

    button.MouseEnter:Connect(function()
        TweenService:Create(
            button,
            TweenInfo.new(0.12),
            { BackgroundTransparency = 0.08 }
        ):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(
            button,
            TweenInfo.new(0.12),
            { BackgroundTransparency = 0 }
        ):Play()
    end)

    return button

end

local function createPanel(parent, name, position, size) local panel =
Instance.new("Frame") panel.Name = name panel.Position = position
panel.Size = size panel.BackgroundColor3 = THEME.surface
panel.BorderSizePixel = 0 panel.Parent = parent addCorner(panel, 13)
addStroke(panel, Color3.fromRGB(113, 124, 164), 0.78, 1) return panel
end

local screenGui = Instance.new("ScreenGui") screenGui.Name = GUI_NAME
screenGui:SetAttribute("Build", "RUY_LOPEZ_OPENING_BOOK")
screenGui.ResetOnSpawn = false screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 1500 screenGui.ZIndexBehavior =
Enum.ZIndexBehavior.Sibling screenGui.Parent = PlayerGui

local mainFrame = Instance.new("Frame") mainFrame.Name = "Hub"
mainFrame.Size = UDim2.fromOffset(500, 560) mainFrame.Position =
UDim2.fromOffset(35, 75) mainFrame.BackgroundColor3 = THEME.background
mainFrame.BorderSizePixel = 0 mainFrame.ClipsDescendants = true
mainFrame.Visible = false mainFrame.Parent = screenGui
addCorner(mainFrame, 18) addStroke(mainFrame, Color3.fromRGB(120, 126,
171), 0.47, 1)

local menuScale = Instance.new("UIScale") menuScale.Scale = 0.92
menuScale.Parent = mainFrame

local header = Instance.new("Frame") header.Name = "DragHeader"
header.Size = UDim2.new(1, 0, 0, 62) header.BackgroundColor3 =
THEME.header header.BorderSizePixel = 0 header.Active = true
header.Parent = mainFrame  

MobileSupport.headerGradient = Instance.new("UIGradient")
MobileSupport.headerGradient.Color = ColorSequence.new({
ColorSequenceKeypoint.new(0, Color3.fromRGB(78, 46, 36)),
ColorSequenceKeypoint.new(0.55, Color3.fromRGB(38, 31, 36)),
ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 22, 28)), })
MobileSupport.headerGradient.Rotation = 8
MobileSupport.headerGradient.Parent = header

MobileSupport.titleLabel = createLabel( header, "Title", "Claude <font color=\"#D97757\">5</font>", UDim2.fromOffset(18, 0), UDim2.new(1, -116, 1, 0), 21,
THEME.text, Enum.Font.GothamBold ) MobileSupport.titleLabel.ZIndex = 3 MobileSupport.titleLabel.RichText = true

local minimizeButton = createButton( header, "Minimize", "—",
UDim2.new(1, -82, 0, 15), UDim2.fromOffset(28, 28), THEME.surface3 )
minimizeButton.TextSize = 17 minimizeButton.ZIndex = 4

local closeButton = createButton( header, "Close", "×", UDim2.new(1,
-46, 0, 15), UDim2.fromOffset(28, 28), Color3.fromRGB(105, 46, 65) )
closeButton.TextSize = 16 closeButton.ZIndex = 4

local tabBar = Instance.new("Frame") tabBar.Name = "Tabs"
tabBar.Position = UDim2.fromOffset(14, 72) tabBar.Size = UDim2.new(1,
-28, 0, 36) tabBar.BackgroundTransparency = 1 tabBar.Parent = mainFrame

local analyzeTab = createButton( tabBar, "AnalyzeTab", "ANALYZE",
UDim2.fromOffset(0, 0), UDim2.new(1 / 3, -5, 1, 0), THEME.accent )

local threatsTab = createButton( tabBar, "ThreatsTab", "THREATS",
UDim2.new(1 / 3, 3, 0, 0), UDim2.new(1 / 3, -6, 1, 0), THEME.surface2 )

local settingsTab = createButton( tabBar, "SettingsTab", "SETTINGS",
UDim2.new(2 / 3, 2, 0, 0), UDim2.new(1 / 3, -2, 1, 0), THEME.surface2 )

local contentHolder = Instance.new("ScrollingFrame") contentHolder.Name
= "Content" contentHolder.Position = UDim2.fromOffset(14, 116)
contentHolder.Size = UDim2.new(1, -28, 0, 394)
contentHolder.BackgroundTransparency = 1 contentHolder.BorderSizePixel =
0 contentHolder.CanvasSize = UDim2.fromOffset(0, 394)
contentHolder.AutomaticCanvasSize = Enum.AutomaticSize.None
contentHolder.ScrollingDirection = Enum.ScrollingDirection.Y
contentHolder.ScrollBarThickness = 4 contentHolder.ScrollBarImageColor3
= THEME.accent2 contentHolder.ScrollBarImageTransparency = 0.25
contentHolder.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
contentHolder.ClipsDescendants = true contentHolder.Parent = mainFrame

local analyzePage = Instance.new("Frame") analyzePage.Name =
"AnalyzePage" analyzePage.Size = UDim2.new(1, 0, 0, 394)
analyzePage.BackgroundTransparency = 1 analyzePage.Parent =
contentHolder

local threatsPage = Instance.new("Frame") threatsPage.Name =
"ThreatsPage" threatsPage.Size = UDim2.new(1, 0, 0, 394)
threatsPage.BackgroundTransparency = 1 threatsPage.Visible = false
threatsPage.Parent = contentHolder

local settingsPage = Instance.new("Frame") settingsPage.Name =
"SettingsPage" settingsPage.Size = UDim2.new(1, 0, 0, 590)
settingsPage.BackgroundTransparency = 1 settingsPage.Visible = false
settingsPage.Parent = contentHolder

MobileSupport.controlRow = Instance.new("Frame")
MobileSupport.controlRow.Size = UDim2.new(1, 0, 0, 34)
MobileSupport.controlRow.BackgroundTransparency = 1
MobileSupport.controlRow.Parent = analyzePage

local aiButton = createButton( MobileSupport.controlRow, "AIButton",
"AI: ON", UDim2.fromOffset(0, 0), UDim2.new(0.22, -4, 1, 0),
THEME.success )

local sideButton = createButton( MobileSupport.controlRow, "SideButton",
"SIDE: WHITE", UDim2.new(0.22, 3, 0, 0), UDim2.new(0.28, -4, 1, 0),
Color3.fromRGB(196, 200, 216) ) sideButton.TextColor3 =
Color3.fromRGB(31, 35, 48)

local modeButton = createButton( MobileSupport.controlRow, "ModeButton",
"MODE: BLITZ", UDim2.new(0.50, 3, 0, 0), UDim2.new(0.28, -4, 1, 0),
THEME.accent )

local autoButton = createButton( MobileSupport.controlRow, "AutoButton",
"AUTO: OFF", UDim2.new(0.78, 3, 0, 0), UDim2.new(0.22, -3, 1, 0),
THEME.surface2 )

local openingLabel = createLabel( analyzePage, "Opening", "Opening: waiting for board scan", UDim2.fromOffset(2, 40), UDim2.new(1, -4, 0,
20), 12, THEME.muted, Enum.Font.GothamMedium )

MobileSupport.evaluationPanel = createPanel( analyzePage,
"EvaluationPanel", UDim2.fromOffset(0, 66), UDim2.new(1, 0, 0, 58) )

MobileSupport.evaluationTitle = createLabel(
MobileSupport.evaluationPanel, "EvaluationTitle", "POSITION EVALUATION",
UDim2.fromOffset(12, 5), UDim2.fromOffset(180, 18), 10, THEME.muted,
Enum.Font.GothamBold )

local evaluationText = createLabel( MobileSupport.evaluationPanel,
"EvaluationText", "EQUAL", UDim2.new(1, -170, 0, 5),
UDim2.fromOffset(158, 18), 11, THEME.text, Enum.Font.GothamBold )
evaluationText.TextXAlignment = Enum.TextXAlignment.Right

local evaluationBar = Instance.new("Frame") evaluationBar.Position =
UDim2.fromOffset(12, 31) evaluationBar.Size = UDim2.new(1, -24, 0, 15)
evaluationBar.BackgroundColor3 = THEME.blackBar
evaluationBar.BorderSizePixel = 0 evaluationBar.ClipsDescendants = true
evaluationBar.Parent = MobileSupport.evaluationPanel
addCorner(evaluationBar, 7)

local whiteEvaluationFill = Instance.new("Frame")
whiteEvaluationFill.Position = UDim2.fromScale(0.5, 0)
whiteEvaluationFill.Size = UDim2.fromScale(0.5, 1)
whiteEvaluationFill.BackgroundColor3 = THEME.whiteBar
whiteEvaluationFill.BorderSizePixel = 0 whiteEvaluationFill.Parent =
evaluationBar

local evaluationMarker = Instance.new("Frame")
evaluationMarker.AnchorPoint = Vector2.new(0.5, 0)
evaluationMarker.Position = UDim2.fromScale(0.5, 0)
evaluationMarker.Size = UDim2.fromOffset(2, 15)
evaluationMarker.BackgroundColor3 = THEME.accent2
evaluationMarker.BorderSizePixel = 0 evaluationMarker.Parent =
evaluationBar

MobileSupport.bestMovePanel = createPanel( analyzePage, "BestMovePanel",
UDim2.fromOffset(0, 132), UDim2.new(1, 0, 0, 84) )

MobileSupport.bestBadge = createLabel( MobileSupport.bestMovePanel,
"Badge", "BEST MOVE", UDim2.fromOffset(13, 7), UDim2.fromOffset(100,
16), 10, THEME.success, Enum.Font.GothamBold )

local bestMoveText = createLabel( MobileSupport.bestMovePanel,
"BestMove", "– → –", UDim2.fromOffset(13, 22), UDim2.fromOffset(210,
32), 24, THEME.text, Enum.Font.GothamBold )

local bestNotationText = createLabel( MobileSupport.bestMovePanel,
"BestNotation", "–", UDim2.new(1, -104, 0, 21), UDim2.fromOffset(88,
32), 22, THEME.accent2, Enum.Font.GothamBold )
bestNotationText.TextXAlignment = Enum.TextXAlignment.Right

local expectedReplyText = createLabel( MobileSupport.bestMovePanel,
"ExpectedReply", "Expected reply: –", UDim2.fromOffset(13, 54),
UDim2.new(1, -26, 0, 20), 11, THEME.muted, Enum.Font.Gotham )

MobileSupport.topMovesTitle = createLabel( analyzePage, "TopMovesTitle",
"TOP 3 CHOICES — click one to preview it", UDim2.fromOffset(2, 223),
UDim2.new(1, -4, 0, 18), 10, THEME.muted, Enum.Font.GothamBold )

local moveRows = {} for index = 1, TOP_MOVE_COUNT do local row =
createButton( analyzePage, "MoveRow" .. tostring(index), tostring(index)
.. ". Waiting for analysis…", UDim2.fromOffset(0, 245 + (index - 1) *
38), UDim2.new(1, 0, 0, 32), index == 1 and THEME.surface3 or
THEME.surface2 ) row.TextXAlignment = Enum.TextXAlignment.Left
row.TextSize = 11 row.Text = " " .. row.Text moveRows[index] = row end

local analyzeButton = createButton( analyzePage, "AnalyzeButton",
"ANALYZE NEAREST BOARD", UDim2.fromOffset(0, 361), UDim2.new(1, 0, 0,
33), THEME.accent ) analyzeButton.TextSize = 13

MobileSupport.analyzeGradient = Instance.new("UIGradient")
MobileSupport.analyzeGradient.Color = ColorSequence.new(THEME.accent,
THEME.accent2) MobileSupport.analyzeGradient.Parent = analyzeButton

MobileSupport.threatHeader = createLabel( threatsPage, "ThreatHeader",
"TACTICAL THREAT SCANNER", UDim2.fromOffset(2, 0), UDim2.new(1, -4, 0,
24), 13, THEME.text, Enum.Font.GothamBold )

MobileSupport.checkPanel = createPanel( threatsPage, "CheckPanel",
UDim2.fromOffset(0, 31), UDim2.new(1, 0, 0, 48) )

local checkStatusLabel = createLabel( MobileSupport.checkPanel,
"CheckStatus", "King status: waiting for scan", UDim2.fromOffset(13, 0),
UDim2.new(1, -26, 1, 0), 13, THEME.muted, Enum.Font.GothamBold )

MobileSupport.hangingPanel = createPanel( threatsPage, "HangingPanel",
UDim2.fromOffset(0, 87), UDim2.new(0.49, 0, 0, 142) )

createLabel( MobileSupport.hangingPanel, "Title", "HANGING PIECES",
UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 18), 10, THEME.danger,
Enum.Font.GothamBold )

local hangingText = createLabel( MobileSupport.hangingPanel, "Body", "No scan yet.", UDim2.fromOffset(12, 28), UDim2.new(1, -24, 1, -36), 11,
THEME.text, Enum.Font.Gotham ) hangingText.TextWrapped = true
hangingText.TextYAlignment = Enum.TextYAlignment.Top

MobileSupport.attackedPanel = createPanel( threatsPage, "AttackedPanel",
UDim2.new(0.51, 0, 0, 87), UDim2.new(0.49, 0, 0, 142) )

createLabel( MobileSupport.attackedPanel, "Title", "UNDER ATTACK",
UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 18), 10, THEME.warning,
Enum.Font.GothamBold )

local attackedText = createLabel( MobileSupport.attackedPanel, "Body",
"No scan yet.", UDim2.fromOffset(12, 28), UDim2.new(1, -24, 1, -36), 11,
THEME.text, Enum.Font.Gotham ) attackedText.TextWrapped = true
attackedText.TextYAlignment = Enum.TextYAlignment.Top

MobileSupport.capturePanel = createPanel( threatsPage, "CapturePanel",
UDim2.fromOffset(0, 237), UDim2.new(1, 0, 0, 72) )

createLabel( MobileSupport.capturePanel, "Title", "BEST AVAILABLE CAPTURE", UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 18), 10,
THEME.success, Enum.Font.GothamBold )

local bestCaptureText = createLabel( MobileSupport.capturePanel,
"Capture", "No scan yet.", UDim2.fromOffset(12, 28), UDim2.new(1, -24,
0, 30), 15, THEME.text, Enum.Font.GothamBold )

MobileSupport.targetPanel = createPanel( threatsPage, "TargetPanel",
UDim2.fromOffset(0, 317), UDim2.new(1, 0, 0, 77) )

createLabel( MobileSupport.targetPanel, "Title", "VALUABLE ENEMY TARGETS", UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 18), 10,
THEME.accent2, Enum.Font.GothamBold )

local targetText = createLabel( MobileSupport.targetPanel, "Targets",
"No scan yet.", UDim2.fromOffset(12, 27), UDim2.new(1, -24, 0, 39), 11,
THEME.text, Enum.Font.Gotham ) targetText.TextWrapped = true

createLabel( settingsPage, "SettingsTitle", "HUB SETTINGS",
UDim2.fromOffset(2, 0), UDim2.new(1, -4, 0, 24), 13, THEME.text,
Enum.Font.GothamBold )

local settingsPanel = createPanel( settingsPage, "SettingsPanel",
UDim2.fromOffset(0, 31), UDim2.new(1, 0, 0, 370) )

local settingsSideButton = createButton( settingsPanel, "SideSetting",
"PLAYING COLOR: WHITE", UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0,
36), Color3.fromRGB(196, 200, 216) ) settingsSideButton.TextColor3 =
Color3.fromRGB(31, 35, 48)

local settingsModeButton = createButton( settingsPanel, "ModeSetting",
"MODE: BLITZ", UDim2.fromOffset(12, 56), UDim2.new(0.5, -18, 0, 36),
THEME.accent )

createButton( settingsPanel, "EngineSwitch", "STYLE: NORMAL",
UDim2.new(0.5, 6, 0, 56), UDim2.new(0.5, -18, 0, 36), THEME.accent2 )

local settingsAutoButton = createButton( settingsPanel, "AutoSetting",
"AUTO: OFF", UDim2.fromOffset(12, 100), UDim2.new(0.5, -18, 0, 36),
THEME.surface2 )

createButton( settingsPanel, "EloSkillSwitch", "ELO SKILL: FULL",
UDim2.new(0.5, 6, 0, 100), UDim2.new(0.5, -18, 0, 36), THEME.success )

local highlightButton = createButton( settingsPanel, "HighlightSetting",
"SQUARE HIGHLIGHTS: ON", UDim2.fromOffset(12, 144), UDim2.new(0.5, -18,
0, 36), THEME.success )

local arrowButton = createButton( settingsPanel, "ArrowSetting", "MOVE ARROW: ON", UDim2.new(0.5, 6, 0, 144), UDim2.new(0.5, -18, 0, 36),
THEME.success )

createButton( settingsPanel, "RankedArrowSwitch", "TOP 3 ARROWS: OFF",
UDim2.fromOffset(12, 188), UDim2.new(0.5, -18, 0, 36), THEME.surface2 )

local resetPositionButton = createButton( settingsPanel,
"ResetPosition", "RESET WINDOW", UDim2.new(0.5, 6, 0, 188),
UDim2.new(0.5, -18, 0, 36), THEME.surface3 )

createButton( settingsPanel, "BestOnlySwitch", "BEST MOVE ONLY: OFF",
UDim2.fromOffset(12, 232), UDim2.new(0.5, -18, 0, 36), THEME.surface2 )
createButton( settingsPanel, "PonderSwitch", "PONDER: OFF",
UDim2.new(0.5, 6, 0, 232), UDim2.new(0.5, -18, 0, 36), THEME.surface2 )
createButton( settingsPanel, "PremoveSwitch", "PREMOVE: needs Ponder",
UDim2.fromOffset(12, 276), UDim2.new(0.5, -18, 0, 36), THEME.surface2 )
createButton( settingsPanel, "NewGameSwitch", "NEW GAME (CLEAR MEMORY)",
UDim2.new(0.5, 6, 0, 276), UDim2.new(0.5, -18, 0, 36), THEME.surface3 )
createButton( settingsPanel, "CopyLogSwitch", "COPY GAME LOG",
UDim2.fromOffset(12, 320), UDim2.new(0.5, -18, 0, 36), THEME.accent2 )
createButton( settingsPanel, "ClearLogSwitch", "CLEAR GAME LOG",
UDim2.new(0.5, 6, 0, 320), UDim2.new(0.5, -18, 0, 36), THEME.surface3 )

MobileSupport.modeInfoPanel = createPanel( settingsPage, "ModeInfo",
UDim2.fromOffset(0, 410), UDim2.new(1, 0, 0, 158) )

local modeInfoText = createLabel( MobileSupport.modeInfoPanel,
"ModeInfoText", "INSTANT • quick answers, obvious moves instantly\nBLITZ • balanced speed and tactics\nDEEP • strongest search\nSTYLE • 13 styles: Normal, Aggressive, Defensive, Passive and Tal, Petrosian, Fischer, Kasparov, Karpov, Carlsen, Capablanca, Morphy, Alien\nPONDER • keeps thinking on the opponent's turn\nPREMOVE • red dashed arrow = move to prepare (needs Ponder)\nBOOK • 115 named opening lines incl. Alien and Martian gambits; the engine checks every book move itself", UDim2.fromOffset(13, 8), UDim2.new(1, -26, 1,
-16), 11, THEME.muted, Enum.Font.Gotham ) modeInfoText.TextWrapped =
true modeInfoText.TextYAlignment = Enum.TextYAlignment.Top

local footerStatus = createLabel( mainFrame, "FooterStatus", "Ready — move near a board and press Analyze.", UDim2.fromOffset(16, 516),
UDim2.new(1, -164, 0, 27), 11, THEME.muted, Enum.Font.Gotham )
footerStatus.TextWrapped = true

createButton( mainFrame, "CopyLinkButton", "COPY LINK", UDim2.new(1,
-128, 0, 516), UDim2.fromOffset(112, 27), THEME.accent )
mainFrame.CopyLinkButton.TextSize = 11 mainFrame.CopyLinkButton.ZIndex =
6

local launcherButton = createButton( screenGui, "Launcher", "♞",
UDim2.new(1, -70, 1, -70), UDim2.fromOffset(52, 52), THEME.accent )
launcherButton.TextSize = 23 launcherButton.Visible = false
launcherButton.ZIndex = 50 addCorner(launcherButton, 17)

local selectedSide = "white" local engineMode = "Blitz" local aiEnabled
= true local autoEnabled = false local analyzing = false local
menuVisible = true local collapsed = false local activeTab = "Analyze"
local CONTENT_PAGE_HEIGHTS = { Analyze = 394, Threats = 394, Settings =
584, }

local function updateContentScrolling(resetPosition) local pageHeight =
CONTENT_PAGE_HEIGHTS[activeTab] or 394 contentHolder.CanvasSize =
UDim2.fromOffset(0, pageHeight)

    local holderHeight = contentHolder.AbsoluteSize.Y
    if holderHeight <= 1 then
        holderHeight = contentHolder.Size.Y.Offset
    end

    contentHolder.ScrollingEnabled = pageHeight > holderHeight + 1

    if resetPosition then
        contentHolder.CanvasPosition = Vector2.zero
    elseif contentHolder.CanvasPosition.Y > math.max(0, pageHeight - holderHeight) then
        contentHolder.CanvasPosition = Vector2.new(
            0,
            math.max(0, pageHeight - holderHeight)
        )
    end

end

local lastTableData = nil local lastBoard = nil local lastCandidates =
{} local lastSearchInfo = nil local lastAnalyzedSignature = nil local
previewedCandidateIndex = 1 local visibilityAnimationId = 0

EngineCore.windowFocused = true EngineCore.suspend2DArrowsUntil = 0
EngineCore.focusRefreshToken = 0 EngineCore.analysisGeneration = 0
EngineCore.activeAnalysisPositionKey = nil
EngineCore.lastObservedPositionKey = nil
EngineCore.pendingBoardPositionKey = nil
EngineCore.pendingBoardStableScans = 0
EngineCore.requiredStableBoardScans = 2
EngineCore.committedVisualPositionKey = nil
EngineCore.committedVisualMoveKey = nil EngineCore.tableIdentityMap =
setmetatable({}, { __mode = "k" }) EngineCore.nextTableIdentity = 0

function EngineCore.getTableIdentity(tableData) if not tableData or not
tableData.model then return "unknown-table" end

    local model = tableData.model
    local identity = EngineCore.tableIdentityMap[model]
    if not identity then
        EngineCore.nextTableIdentity += 1
        local folderName = tableData.tablesetFolder
            and tableData.tablesetFolder.Name
            or "Tableset"
        identity = folderName
            .. "#"
            .. tostring(EngineCore.nextTableIdentity)
            .. "@"
            .. tostring(tableData.index or 0)
        EngineCore.tableIdentityMap[model] = identity
    end

    return identity

end

function EngineCore.positionKey(tableData, board, side) if not tableData
or not tableData.model or not board then return nil end

    return EngineCore.getTableIdentity(tableData)
        .. "|"
        .. boardHash(board, side)
        .. "|"
        .. BoardTracker.fenStateKey()

end

function EngineCore.analysisIsCurrent(generation, positionKey) return
generation == EngineCore.analysisGeneration and (not positionKey or
EngineCore.activeAnalysisPositionKey == positionKey) end

function EngineCore.abortActiveAnalysis(clearVisuals)
EngineCore.analysisGeneration += 1 EngineCore.activeAnalysisPositionKey
= nil analyzing = false analyzeButton.Active = true analyzeButton.Text =
"ANALYZE NEAREST BOARD"

    if clearVisuals then
        hideBoardEffects()
    end

end

function EngineCore.get2DBoardGeometrySignature() local camera =
Workspace.CurrentCamera local viewport = camera and camera.ViewportSize
or Vector2.zero local names = { "a1", "h1", "a8", "h8" } local values =
{ math.floor(viewport.X + 0.5), math.floor(viewport.Y + 0.5), }

    for _, name in ipairs(names) do
        local square = find2DBoardSquare(name)
        if not square or not square:IsA("GuiObject") then
            return nil
        end

        local position = square.AbsolutePosition
        local size = square.AbsoluteSize
        if size.X <= 1 or size.Y <= 1 then
            return nil
        end

        table.insert(values, math.floor(position.X + 0.5))
        table.insert(values, math.floor(position.Y + 0.5))
        table.insert(values, math.floor(size.X + 0.5))
        table.insert(values, math.floor(size.Y + 0.5))
    end

    return table.concat(values, ":")

end

function EngineCore.refreshBoardEffectsAfterWindowFocus(token) local
lastSignature = nil local stableFrames = 0 local deadline = os.clock() +
0.50

    while token == EngineCore.focusRefreshToken
        and EngineCore.windowFocused
        and os.clock() < deadline do
        RunService.RenderStepped:Wait()

        local signature = EngineCore.get2DBoardGeometrySignature()
        if signature and signature == lastSignature then
            stableFrames += 1
        else
            lastSignature = signature
            stableFrames = signature and 1 or 0
        end

        if stableFrames >= 2 then
            break
        end
    end

    if token ~= EngineCore.focusRefreshToken or not EngineCore.windowFocused then
        return
    end

    EngineCore.suspend2DArrowsUntil = 0
    if lastCandidates[previewedCandidateIndex] and lastTableData then
        showMoveEffects(lastTableData, lastCandidates[previewedCandidateIndex].move)
        EngineCore.showRankedMoveArrows(lastTableData, lastCandidates)
    end

    if EngineCore.ranked2DOverlay then
        EngineCore.ranked2DOverlay.Enabled = true
    end

end

MobileSupport.windowFocusReleasedConnection =
UserInputService.WindowFocusReleased:Connect(function()
EngineCore.windowFocused = false EngineCore.focusRefreshToken += 1
EngineCore.suspend2DArrowsUntil = math.huge

        -- Keep square highlights parented to their squares so they remain
        -- available immediately when Roblox regains focus. Only hide the
        -- absolute-position ranked-arrow layer until its geometry is refreshed.
        if EngineCore.ranked2DOverlay then
            EngineCore.ranked2DOverlay.Enabled = false
        end
    end)

MobileSupport.windowFocusedConnection =
UserInputService.WindowFocused:Connect(function()
EngineCore.windowFocused = true EngineCore.focusRefreshToken += 1
EngineCore.suspend2DArrowsUntil = os.clock() + 0.05 local token =
EngineCore.focusRefreshToken task.spawn(function()
EngineCore.refreshBoardEffectsAfterWindowFocus(token) end) end)

MobileSupport.suggestionWatchActive = false
MobileSupport.suggestionResolved = true
MobileSupport.suggestionTableIndex = nil
MobileSupport.suggestionOriginalHash = nil
MobileSupport.suggestionExpectedHashes = {}
MobileSupport.pendingBoardChangeHash = nil
MobileSupport.pendingBoardChangeScans = 0
MobileSupport.staleSuggestionWarningShown = false

local function setStatus(text, color) footerStatus.Text = text
footerStatus.TextColor3 = color or THEME.muted end

function MobileSupport.clearSuggestionWatch()
MobileSupport.suggestionWatchActive = false
MobileSupport.suggestionResolved = true
MobileSupport.suggestionTableIndex = nil
MobileSupport.suggestionOriginalHash = nil
MobileSupport.suggestionExpectedHashes = {}
MobileSupport.pendingBoardChangeHash = nil
MobileSupport.pendingBoardChangeScans = 0
MobileSupport.staleSuggestionWarningShown = false

    if searchInfo and searchInfo.book then
        MobileSupport.bestBadge.Text = "BOOK MOVE"
        MobileSupport.bestBadge.TextColor3 = THEME.accent2
    else
        MobileSupport.bestBadge.Text = EngineCore.eloSkill ~= "Full"
            and ("ELO " .. string.upper(EngineCore.eloSkill))
            or "BEST MOVE"
        MobileSupport.bestBadge.TextColor3 = EngineCore.eloSkill ~= "Full"
            and THEME.warning
            or THEME.success
    end

end

function MobileSupport.armSuggestionWatch() local candidate =
lastCandidates[previewedCandidateIndex] if not lastBoard or not
lastTableData or not candidate or not candidate.move then
MobileSupport.clearSuggestionWatch() return end

    MobileSupport.suggestionWatchActive = true
    MobileSupport.suggestionResolved = false
    MobileSupport.suggestionTableIndex = lastTableData.index
    MobileSupport.suggestionOriginalHash = boardHash(lastBoard, "white")
    MobileSupport.suggestionExpectedHashes = {}
    MobileSupport.pendingBoardChangeHash = nil
    MobileSupport.pendingBoardChangeScans = 0
    MobileSupport.staleSuggestionWarningShown = false

    MobileSupport.bestBadge.Text = "BEST MOVE"
    MobileSupport.bestBadge.TextColor3 = THEME.success

    local suggestedBoard = candidate.move._nextBoard or applyMove(lastBoard, candidate.move)
    MobileSupport.suggestionExpectedHashes[boardHash(suggestedBoard, "white")] = true

    for _, reply in ipairs(generateLegalMoves(suggestedBoard, opposite(selectedSide))) do
        local replyBoard = reply._nextBoard or applyMove(suggestedBoard, reply)
        MobileSupport.suggestionExpectedHashes[boardHash(replyBoard, "white")] = true
    end

end

function MobileSupport.checkSuggestionBoardChange(board, tableData) if
not MobileSupport.suggestionWatchActive or
MobileSupport.suggestionResolved or
MobileSupport.staleSuggestionWarningShown or not board or not tableData
or tableData.index ~= MobileSupport.suggestionTableIndex then return end

    local currentHash = boardHash(board, "white")

    if currentHash == MobileSupport.suggestionOriginalHash then
        MobileSupport.pendingBoardChangeHash = nil
        MobileSupport.pendingBoardChangeScans = 0
        return
    end

    if MobileSupport.suggestionExpectedHashes[currentHash] then
        MobileSupport.suggestionResolved = true
        MobileSupport.pendingBoardChangeHash = nil
        MobileSupport.pendingBoardChangeScans = 0
        return
    end

    if MobileSupport.pendingBoardChangeHash == currentHash then
        MobileSupport.pendingBoardChangeScans += 1
    else
        MobileSupport.pendingBoardChangeHash = currentHash
        MobileSupport.pendingBoardChangeScans = 1
    end

    if MobileSupport.pendingBoardChangeScans < 3 then
        return
    end

    MobileSupport.staleSuggestionWarningShown = true
    MobileSupport.suggestionResolved = true
    MobileSupport.bestBadge.Text = "BOARD CHANGED"
    MobileSupport.bestBadge.TextColor3 = THEME.danger
    setStatus(
        "Warning: the board changed before the suggested move was played. Analyze again.",
        THEME.warning
    )

end

local function formatScore(score) if math.abs(score) >= MATE_SCORE - 100
then return score > 0 and "WHITE MATE" or "BLACK MATE" end

    if math.abs(score) < 5 then
        return "EQUAL"
    end

    if score > 0 then
        return "WHITE +" .. string.format("%.2f", score / 100)
    end

    return "BLACK +" .. string.format("%.2f", math.abs(score) / 100)

end

local function scoreForSelectedSide(score) return selectedSide ==
"white" and score or -score end

local function candidateTag(candidate, bestCandidate) if candidate and
candidate.book then return "BOOK" end

    if candidate and candidate.eloPrimary then
        return "ELO PICK"
    end

    if candidate and candidate.fullStrengthBest then
        return "FULL BEST"
    end

    if not bestCandidate then
        return "CHOICE"
    end

    local loss
    if selectedSide == "white" then
        loss = bestCandidate.score - candidate.score
    else
        loss = candidate.score - bestCandidate.score
    end

    if loss <= 20 then
        return "BEST"
    elseif loss <= 75 then
        return "STRONG"
    elseif loss <= 180 then
        return "PLAYABLE"
    end
    return "RISKY"

end

local function setEvaluationBar(score) local ratio = math.clamp(0.5 +
score / 2200, 0.05, 0.95)

    TweenService:Create(
        whiteEvaluationFill,
        TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.fromScale(1 - ratio, 0),
            Size = UDim2.fromScale(ratio, 1),
        }
    ):Play()

    TweenService:Create(
        evaluationMarker,
        TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.fromScale(1 - ratio, 0) }
    ):Play()

    evaluationText.Text = formatScore(score)

end

local function updateSideButtons() local white = selectedSide == "white"

    sideButton.Text = white and "SIDE: WHITE" or "SIDE: BLACK"
    sideButton.BackgroundColor3 = white
        and Color3.fromRGB(196, 200, 216)
        or Color3.fromRGB(44, 48, 62)
    sideButton.TextColor3 = white
        and Color3.fromRGB(31, 35, 48)
        or THEME.text

    settingsSideButton.Text = white
        and "PLAYING COLOR: WHITE"
        or "PLAYING COLOR: BLACK"
    settingsSideButton.BackgroundColor3 = sideButton.BackgroundColor3
    settingsSideButton.TextColor3 = sideButton.TextColor3

end

local function updateModeButtons() modeButton.Text = "MODE:" ..
string.upper(engineMode) settingsModeButton.Text = "MODE:" ..
string.upper(engineMode) end

local function updateEnginePreferenceButton()
    local style = EngineCore.enginePreference
    local button = settingsPanel.EngineSwitch
    button.Text = "STYLE: " .. string.upper(style)
    button.TextScaled = true
    if not button:FindFirstChildOfClass("UITextSizeConstraint") then
        local constraint = Instance.new("UITextSizeConstraint")
        constraint.MaxTextSize = 13
        constraint.MinTextSize = 8
        constraint.Parent = button
    end

    local hot = { Aggressive = true, Tal = true, Kasparov = true, Morphy = true, Alien = true }
    local solid = { Defensive = true, Petrosian = true }
    local quiet = { Passive = true, Karpov = true, Capablanca = true }
    if hot[style] then
        button.BackgroundColor3 = THEME.danger
    elseif solid[style] then
        button.BackgroundColor3 = THEME.success
    elseif quiet[style] then
        button.BackgroundColor3 = THEME.warning
    else
        button.BackgroundColor3 = THEME.accent
    end
end

local function updateEloSkillButton() local skill = EngineCore.eloSkill
or "Full" settingsPanel.EloSkillSwitch.Text = "ELO SKILL:" ..
string.upper(skill)

    if skill == "Full" then
        settingsPanel.EloSkillSwitch.BackgroundColor3 = THEME.success
    elseif skill == "Expert" or skill == "Advanced" then
        settingsPanel.EloSkillSwitch.BackgroundColor3 = THEME.accent2
    elseif skill == "Intermediate" then
        settingsPanel.EloSkillSwitch.BackgroundColor3 = THEME.accent
    else
        settingsPanel.EloSkillSwitch.BackgroundColor3 = THEME.warning
    end

end

local function updateAutoButtons() autoButton.Text = autoEnabled and
"AUTO: ON" or "AUTO: OFF" autoButton.BackgroundColor3 = autoEnabled and
THEME.success or THEME.surface2

    settingsAutoButton.Text = autoEnabled
        and "AUTO: ON"
        or "AUTO: OFF"
    settingsAutoButton.BackgroundColor3 = autoButton.BackgroundColor3

end

local function updateAIButton() aiButton.Text = aiEnabled and "AI: ON"
or "AI: OFF" aiButton.BackgroundColor3 = aiEnabled and THEME.success or
THEME.danger end

local function updateEffectButtons() highlightButton.Text =
highlightsEnabled and "SQUARE HIGHLIGHTS: ON" or "SQUARE HIGHLIGHTS: OFF" highlightButton.BackgroundColor3 = highlightsEnabled and
THEME.success or THEME.surface2

    arrowButton.Text = arrowEnabled and "MOVE ARROW: ON" or "MOVE ARROW: OFF"
    arrowButton.BackgroundColor3 = arrowEnabled and THEME.success or THEME.surface2

    settingsPanel.RankedArrowSwitch.Text = EngineCore.multiArrowEnabled
        and "TOP 3 ARROWS: ON"
        or "TOP 3 ARROWS: OFF"
    settingsPanel.RankedArrowSwitch.BackgroundColor3 = EngineCore.multiArrowEnabled
        and THEME.success
        or THEME.surface2

end

local function selectTab(tabName) activeTab = tabName

    analyzePage.Visible = tabName == "Analyze"
    threatsPage.Visible = tabName == "Threats"
    settingsPage.Visible = tabName == "Settings"
    updateContentScrolling(true)

    analyzeTab.BackgroundColor3 = tabName == "Analyze" and THEME.accent or THEME.surface2
    threatsTab.BackgroundColor3 = tabName == "Threats" and THEME.accent or THEME.surface2
    settingsTab.BackgroundColor3 = tabName == "Settings" and THEME.accent or THEME.surface2

end

local function setMenuVisible(visible)

    visibilityAnimationId += 1
    local animationId = visibilityAnimationId
    menuVisible = visible

    if visible then
        launcherButton.Visible = false
        mainFrame.Visible = true
        menuScale.Scale = math.max(0.5, MobileSupport.menuTargetScale - 0.08)

        TweenService:Create(
            menuScale,
            TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = MobileSupport.menuTargetScale }
        ):Play()
    else
        TweenService:Create(
            menuScale,
            TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = math.max(0.5, MobileSupport.menuTargetScale - 0.08) }
        ):Play()

        task.delay(0.14, function()
            if animationId ~= visibilityAnimationId then
                return
            end
            mainFrame.Visible = false
            launcherButton.Visible = true
        end)
    end

end

local clearMoveRows

task.defer(function() setMenuVisible(true) end)

local function setCollapsed(value) collapsed = value

    if value then
        tabBar.Visible = false
        contentHolder.Visible = false
        footerStatus.Visible = false
        mainFrame.CopyLinkButton.Visible = false

        local copyBox = mainFrame:FindFirstChild("CopyLinkBox")
        if copyBox then
            copyBox.Visible = false
        end

        minimizeButton.Text = "+"

        TweenService:Create(
            mainFrame,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(MobileSupport.BASE_MENU_WIDTH, MobileSupport.COLLAPSED_MENU_HEIGHT) }
        ):Play()
    else
        minimizeButton.Text = "—"

        local tween = TweenService:Create(
            mainFrame,
            TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(MobileSupport.BASE_MENU_WIDTH, MobileSupport.expandedFrameHeight) }
        )
        tween:Play()

        task.delay(0.12, function()
            if not collapsed then
                tabBar.Visible = true
                contentHolder.Visible = true
                footerStatus.Visible = true
                mainFrame.CopyLinkButton.Visible = true
            end
        end)
    end

end

local desiredMenuPosition = Vector2.new(35, 75) local
currentMenuPosition = desiredMenuPosition local dragging = false local
dragInput = nil local dragStartPosition = nil local menuStartPosition =
nil

local function getViewportSize() local camera = Workspace.CurrentCamera
return camera and camera.ViewportSize or Vector2.new(1280, 720) end

function MobileSupport.displayedMenuHeight() return collapsed and
MobileSupport.COLLAPSED_MENU_HEIGHT or MobileSupport.expandedFrameHeight
end

local function clampMenuPosition(position) local viewport =
getViewportSize() local width = MobileSupport.BASE_MENU_WIDTH *
MobileSupport.menuTargetScale local height =
MobileSupport.displayedMenuHeight() * MobileSupport.menuTargetScale

    return Vector2.new(
        math.clamp(position.X, 8, math.max(8, viewport.X - width - 8)),
        math.clamp(position.Y, 8, math.max(8, viewport.Y - height - 8))
    )

end

local function resetWindowPosition() local viewport = getViewportSize()
local visibleWidth = MobileSupport.BASE_MENU_WIDTH *
MobileSupport.menuTargetScale local visibleHeight =
MobileSupport.displayedMenuHeight() * MobileSupport.menuTargetScale

    if UserInputService.TouchEnabled then
        desiredMenuPosition = clampMenuPosition(Vector2.new(
            (viewport.X - visibleWidth) * 0.5,
            math.max(8, (viewport.Y - visibleHeight) * 0.5)
        ))
    else
        desiredMenuPosition = clampMenuPosition(Vector2.new(
            viewport.X - visibleWidth - 20,
            70
        ))
    end

    currentMenuPosition = desiredMenuPosition

end

function MobileSupport.updateResponsiveLayout(recenter) local viewport =
getViewportSize() local horizontalScale = (viewport.X - 16) /
MobileSupport.BASE_MENU_WIDTH MobileSupport.menuTargetScale =
math.clamp( math.min(MobileSupport.BASE_MENU_SCALE, horizontalScale),
0.52, MobileSupport.BASE_MENU_SCALE )

    local availableLogicalHeight = (viewport.Y - 16) / MobileSupport.menuTargetScale
    MobileSupport.expandedFrameHeight = math.floor(math.clamp(
        availableLogicalHeight,
        350,
        MobileSupport.BASE_MENU_HEIGHT
    ))

    local targetHeight = MobileSupport.displayedMenuHeight()
    mainFrame.Size = UDim2.fromOffset(MobileSupport.BASE_MENU_WIDTH, targetHeight)

    local contentHeight = math.max(174, MobileSupport.expandedFrameHeight - 166)
    contentHolder.Size = UDim2.new(1, -28, 0, contentHeight)
    updateContentScrolling(false)
    footerStatus.Position = UDim2.fromOffset(16, MobileSupport.expandedFrameHeight - 44)
    mainFrame.CopyLinkButton.Position = UDim2.new(1, -128, 0, MobileSupport.expandedFrameHeight - 44)

    local copyBox = mainFrame:FindFirstChild("CopyLinkBox")
    if copyBox then
        copyBox.Position = UDim2.new(1, -250, 0, MobileSupport.expandedFrameHeight - 48)
    end

    if UserInputService.TouchEnabled then
        launcherButton.Size = UDim2.fromOffset(58, 58)
        launcherButton.Position = UDim2.new(1, -74, 1, -74)
    else
        launcherButton.Size = UDim2.fromOffset(52, 52)
        launcherButton.Position = UDim2.new(1, -70, 1, -70)
    end

    if mainFrame.Visible then
        menuScale.Scale = MobileSupport.menuTargetScale
    end

    if recenter then
        resetWindowPosition()
    else
        desiredMenuPosition = clampMenuPosition(desiredMenuPosition)
        currentMenuPosition = clampMenuPosition(currentMenuPosition)
    end

end

function MobileSupport.connectResponsiveViewport() if
MobileSupport.responsiveViewportConnection then
MobileSupport.responsiveViewportConnection:Disconnect()
MobileSupport.responsiveViewportConnection = nil end

    local camera = Workspace.CurrentCamera
    if camera then
        MobileSupport.responsiveViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            MobileSupport.updateResponsiveLayout(true)
        end)
    end

    MobileSupport.updateResponsiveLayout(true)

end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(MobileSupport.connectResponsiveViewport)
task.defer(MobileSupport.connectResponsiveViewport)

header.InputBegan:Connect(function(input) if input.UserInputType ==
Enum.UserInputType.MouseButton1 or input.UserInputType ==
Enum.UserInputType.Touch then dragging = true dragInput = input
dragStartPosition = input.Position menuStartPosition =
desiredMenuPosition end end)

header.InputChanged:Connect(function(input) if input.UserInputType ==
Enum.UserInputType.MouseMovement or input.UserInputType ==
Enum.UserInputType.Touch then dragInput = input end end)

UserInputService.InputChanged:Connect(function(input) if dragging and
input == dragInput then local delta = input.Position - dragStartPosition
desiredMenuPosition = clampMenuPosition( menuStartPosition +
Vector2.new(delta.X, delta.Y) ) end end)

UserInputService.InputEnded:Connect(function(input) if
input.UserInputType == Enum.UserInputType.MouseButton1 or
input.UserInputType == Enum.UserInputType.Touch then dragging = false
dragInput = nil end end)

RunService.RenderStepped:Connect(function(deltaTime) local interpolation
= math.clamp(deltaTime * 24, 0, 1) currentMenuPosition =
currentMenuPosition:Lerp(desiredMenuPosition, interpolation)
mainFrame.Position = UDim2.fromOffset(
math.floor(currentMenuPosition.X + 0.5),
math.floor(currentMenuPosition.Y + 0.5) ) end)

clearMoveRows = function() for index, row in ipairs(moveRows) do
row.Text = " " .. tostring(index) .. ". No move available"
row.BackgroundColor3 = index == 1 and THEME.surface3 or THEME.surface2
end end

function MobileSupport.detectSideFrom2DBoard() local boardGui =
PlayerGui:FindFirstChild("2DBoard") if not boardGui then return nil, nil
end

    if boardGui:IsA("LayerCollector") and not boardGui.Enabled then
        return nil, boardGui
    end

    local a1 = boardGui:FindFirstChild("a1", true)
    local a8 = boardGui:FindFirstChild("a8", true)
    if not a1 or not a8 or not a1:IsA("GuiObject") or not a8:IsA("GuiObject") then
        return nil, boardGui
    end

    if a1.AbsoluteSize.X <= 1 or a1.AbsoluteSize.Y <= 1
        or a8.AbsoluteSize.X <= 1 or a8.AbsoluteSize.Y <= 1 then
        return nil, boardGui
    end

    local verticalDifference = a1.AbsolutePosition.Y - a8.AbsolutePosition.Y
    if math.abs(verticalDifference) < 8 then
        return nil, boardGui
    end

    return verticalDifference > 0 and "white" or "black", boardGui

end

function MobileSupport.refreshDetectedSide(showStatus) local
detectedSide, boardGui = MobileSupport.detectSideFrom2DBoard() if not
detectedSide then return false end

    local newBoard = boardGui ~= MobileSupport.detectedSideBoardGui
    local orientationChanged = detectedSide ~= MobileSupport.lastDetectedSide
    if not newBoard and not orientationChanged then
        return false
    end

    MobileSupport.detectedSideBoardGui = boardGui
    MobileSupport.lastDetectedSide = detectedSide

    local sideChanged = selectedSide ~= detectedSide
    selectedSide = detectedSide
    updateSideButtons()
    lastAnalyzedSignature = nil
    lastCandidates = {}
    MobileSupport.clearSuggestionWatch()
    clearMoveRows()
    hideBoardEffects()

    bestMoveText.Text = "-- → --"
    bestNotationText.Text = "--"
    expectedReplyText.Text = "Expected reply: --"

    if showStatus or not analyzing then
        setStatus(
            "Playing color auto-detected: " .. string.upper(selectedSide) .. ".",
            THEME.success
        )
    end

    return sideChanged

end

local function updateThreatPage(board) local report = scanThreats(board,
selectedSide)

    checkStatusLabel.Text = report.inCheck
        and string.upper(selectedSide) .. " KING IS IN CHECK"
        or string.upper(selectedSide) .. " king is currently safe"
    checkStatusLabel.TextColor3 = report.inCheck and THEME.danger or THEME.success

    hangingText.Text = summarizeThreatList(report.hanging, "No hanging pieces detected.")
    attackedText.Text = summarizeThreatList(report.attacked, "No pieces are currently attacked.")
    targetText.Text = summarizeThreatList(report.targets, "No valuable target is directly attacked.")

    if report.bestCapture then
        bestCaptureText.Text = moveToDisplay(report.bestCapture)
            .. "   ("
            .. moveToNotation(board, report.bestCapture)
            .. ")"
    else
        bestCaptureText.Text = "No legal capture is available."
    end

end

local function previewCandidate(index) local candidate =
lastCandidates[index] if not candidate or not lastTableData or not
lastBoard then return end

    previewedCandidateIndex = index

    for rowIndex, row in ipairs(moveRows) do
        row.BackgroundColor3 = rowIndex == index and THEME.accent or THEME.surface2
    end

    bestMoveText.Text = moveToDisplay(candidate.move)
    bestNotationText.Text = moveToNotation(lastBoard, candidate.move)

    if candidate.move.kingCapture then
        expectedReplyText.Text = "Game-ending move: capture the enemy king"
    elseif candidate.reply then
        local nextBoard = applyMove(lastBoard, candidate.move)
        expectedReplyText.Text = "Expected reply: "
            .. moveToDisplay(candidate.reply)
            .. "  ("
            .. moveToNotation(nextBoard, candidate.reply)
            .. ")"
    else
        expectedReplyText.Text = "Expected reply: not reached at this depth"
    end

    setEvaluationBar(candidate.score)
    showMoveEffects(lastTableData, candidate.move)
    EngineCore.showRankedMoveArrows(lastTableData, lastCandidates)

    if lastSearchInfo
        and not lastSearchInfo.thinking
        and lastSearchInfo.visualPositionKey then
        EngineCore.committedVisualPositionKey = lastSearchInfo.visualPositionKey
        EngineCore.committedVisualMoveKey = EngineCore.moveKey(candidate.move)
    end

    if lastSearchInfo and lastSearchInfo.thinking then
        MobileSupport.clearSuggestionWatch()
        local quick = lastSearchInfo.quick == true
        local quickSafe = quick and lastSearchInfo.quickSafe == true
        MobileSupport.bestBadge.Text = quick
            and (quickSafe and "SAFE QUICK" or "QUICK CHECK")
            or "THINKING"
        MobileSupport.bestBadge.TextColor3 = quick and THEME.warning or THEME.accent2
    else
        MobileSupport.armSuggestionWatch()
    end

end

function EngineCore.refreshPremoveArrow()
    local tableData = EngineCore.premove.tableData or lastTableData
    if not tableData then
        return
    end
    EngineCore.showRankedMoveArrows(tableData, lastCandidates or {})
end

local function displayCandidates(board, tableData, candidates,
searchInfo) lastBoard = board lastTableData = tableData lastCandidates =
candidates lastSearchInfo = searchInfo EngineCore.fullCandidates = candidates
    EngineCore.openingTag = nil
    if searchInfo and not searchInfo.thinking then
        if searchInfo.gambit then
            EngineCore.openingTag = { text = string.upper(searchInfo.gambit.name), uci = searchInfo.gambit.uci, warm = true }
        elseif searchInfo.opening and candidates[1] and candidates[1].move then
            EngineCore.openingTag = { text = string.upper(searchInfo.opening), uci = moveToCoordinates(candidates[1].move), warm = false }
        end
    end
    if EngineCore.bestMoveOnly and #candidates > 1 then candidates = { candidates[1] } lastCandidates = candidates end

    clearMoveRows()

    if #candidates == 0 then
        MobileSupport.clearSuggestionWatch()
        bestMoveText.Text = "-- → --"
        bestNotationText.Text = "--"
        expectedReplyText.Text = "Expected reply: --"
        setEvaluationBar(0)
        hideBoardEffects()
        return
    end

    local bestCandidate = candidates[1]
    local thinking = searchInfo and searchInfo.thinking == true
    local quick = thinking and searchInfo.quick == true
    local quickSafe = quick and searchInfo.quickSafe == true

    for index, candidate in ipairs(candidates) do
        local tag = thinking
            and (quick
                and (quickSafe and "SAFE" or "CHECK")
                or ((searchInfo.depth or 0) > 0
                    and ("DEPTH " .. tostring(searchInfo.depth))
                    or "THINKING"))
            or candidateTag(candidate, bestCandidate)
        local selectedEvaluation = scoreForSelectedSide(candidate.score) / 100
        local evaluationPrefix = selectedEvaluation > 0 and "+" or ""

        moveRows[index].Text = string.format(
            "  %d.  %s   %-7s   %-8s   %s%.2f",
            index,
            moveToDisplay(candidate.move),
            moveToNotation(board, candidate.move),
            tag,
            evaluationPrefix,
            selectedEvaluation
        )
    end

    if thinking then
        -- Live search updates should refresh the move list and evaluation only.
        -- Rebuilding board highlights and arrows at every completed depth made
        -- them flicker, briefly disappear, and jump between provisional moves.
        previewedCandidateIndex = 1

        for rowIndex, row in ipairs(moveRows) do
            row.BackgroundColor3 = rowIndex == 1 and THEME.accent or THEME.surface2
        end

        bestMoveText.Text = moveToDisplay(bestCandidate.move)
        bestNotationText.Text = moveToNotation(board, bestCandidate.move)

        if bestCandidate.reply then
            local nextBoard = applyMove(board, bestCandidate.move)
            expectedReplyText.Text = "Expected reply: "
                .. moveToDisplay(bestCandidate.reply)
                .. "  ("
                .. moveToNotation(nextBoard, bestCandidate.reply)
                .. ")"
        else
            expectedReplyText.Text = "Expected reply: still calculating"
        end

        setEvaluationBar(bestCandidate.score)
        MobileSupport.clearSuggestionWatch()
        MobileSupport.bestBadge.Text = quick
            and (quickSafe and "SAFE QUICK" or "QUICK CHECK")
            or "THINKING"
        MobileSupport.bestBadge.TextColor3 = quick and THEME.warning or THEME.accent2
        return
    end

    -- Only finalized candidates replace the board highlights and ranked arrows.
    -- Always publish the current verified #1 move. The previous implementation
    -- preserved an older committed move whenever it was still somewhere in the
    -- top three; that could make the display look "safe locked" on a weaker
    -- line after a stronger re-analysis completed.
    local finalPreviewIndex = 1
    local visualPositionKey = searchInfo and searchInfo.visualPositionKey or nil

    previewCandidate(finalPreviewIndex)
    if visualPositionKey then
        EngineCore.committedVisualPositionKey = visualPositionKey
        EngineCore.committedVisualMoveKey = EngineCore.moveKey(
            candidates[finalPreviewIndex].move
        )
        EngineCore.committedVisualAt = os.clock()
    end
    MobileSupport.bestBadge.Text = EngineCore.eloSkill ~= "Full"
        and ("ELO " .. string.upper(EngineCore.eloSkill))
        or "BEST MOVE"
    MobileSupport.bestBadge.TextColor3 = EngineCore.eloSkill ~= "Full"
        and THEME.warning
        or THEME.success


    if EngineCore.recordAnalysis then
        pcall(EngineCore.recordAnalysis, board, selectedSide, EngineCore.fullCandidates or candidates, searchInfo, engineMode)
    end
    if EngineCore.afterFinalDisplay then
        pcall(EngineCore.afterFinalDisplay, board, tableData, candidates, searchInfo, selectedSide, engineMode)
    end

end
local function hasBothKings(board) return findKing(board, "white") ~=
nil and findKing(board, "black") ~= nil end

local function finishAnalysisButton(generation) if generation and
generation ~= EngineCore.analysisGeneration then return end

    analyzeButton.Text = "ANALYZE NEAREST BOARD"
    analyzeButton.Active = true
    analyzing = false

end

local function runAnalysis(generation) if generation ~=
EngineCore.analysisGeneration then return end

    if not aiEnabled then
        setStatus("Turn AI back on before analyzing.", THEME.warning)
        finishAnalysisButton(generation)
        return
    end

    MobileSupport.refreshDetectedSide(false)

    local analysisSide = selectedSide
    local analysisMode = engineMode
    local analysisPreference = EngineCore.enginePreference

    analyzeButton.Active = false
    analyzeButton.Text = "READING BOARD..."
    setStatus("Finding the nearest chess table...", THEME.accent2)

    task.wait()
    if generation ~= EngineCore.analysisGeneration then
        return
    end

    local tableData, tableError = findNearestChessTable()
    if not tableData then
        setStatus(tableError or "No chess table was found.", THEME.danger)
        finishAnalysisButton(generation)
        return
    end

    local board, diagnostics = BoardTracker.readStableBoard(tableData, 6)

    if not board or not diagnostics or diagnostics.mappedPieces == 0 then
        setStatus("No pieces could be mapped to the nearest board.", THEME.danger)
        finishAnalysisButton(generation)
        return
    end

    if diagnostics.valid == false or not hasBothKings(board) then
        setStatus(
            diagnostics.validationError
                or ("Mapped " .. tostring(diagnostics.mappedPieces)
                    .. " pieces, but the position failed validation."),
            THEME.danger
        )
        finishAnalysisButton(generation)
        return
    end

    if diagnostics.stable == false then
        setStatus(
            "Board is still moving — waiting for three identical live 2D scans.",
            THEME.warning
        )
        finishAnalysisButton(generation)
        return
    end

    local clockTurn = BoardTracker.sampleClockTurn(tableData)
    BoardTracker.observeBoard(
        board,
        clockTurn,
        tableData.model
    )

    local detectedTurn = BoardTracker.getSideToMove(nil)
    local whiteInCheck = isKingInCheck(board, "white")
    local blackInCheck = isKingInCheck(board, "black")
    local preliminarySide = detectedTurn or selectedSide
    local chessClubKingCaptures = BoardTracker.getChessClubKingCaptures(
        board,
        preliminarySide
    )

    -- Clock text can lag by one update during fast play. When that happens,
    -- also test the player's auto-detected color before allowing a stale clock
    -- sample to hide an immediate king capture.
    if #chessClubKingCaptures == 0 and preliminarySide ~= selectedSide then
        local selectedSideCaptures = BoardTracker.getChessClubKingCaptures(
            board,
            selectedSide
        )
        if #selectedSideCaptures > 0 then
            preliminarySide = selectedSide
            chessClubKingCaptures = selectedSideCaptures
        end
    end

    local chessClubCaptureAvailable = #chessClubKingCaptures > 0

    -- Standard check-state validation remains active everywhere except the
    -- exact Chess Club position where a direct king capture is available. The
    -- exception is intentionally narrow so ordinary Stockfish analysis keeps
    -- standard-chess legality and quality.
    if not chessClubCaptureAvailable then
        if whiteInCheck and blackInCheck then
            setStatus(
                "The live board is temporarily illegal — both kings appear in check.",
                THEME.danger
            )
            finishAnalysisButton(generation)
            return
        end

        -- A checked king must be the side to move in standard chess.
        local checkTurn = whiteInCheck and "white"
            or (blackInCheck and "black" or nil)
        if checkTurn then
            detectedTurn = checkTurn
            BoardTracker.confirmedTurn = checkTurn
            BoardTracker.turnConfidence = math.max(
                BoardTracker.turnConfidence or 0,
                2
            )
        end
    end

    if detectedTurn and detectedTurn ~= selectedSide
        and not chessClubCaptureAvailable then
        setStatus(
            "Waiting for " .. string.upper(selectedSide)
                .. " to move — the live position shows "
                .. string.upper(detectedTurn) .. " to move.",
            THEME.warning
        )
        finishAnalysisButton(generation)
        return
    end

    analysisSide = chessClubCaptureAvailable
        and preliminarySide
        or (detectedTurn or selectedSide)

    -- Re-evaluate the direct-capture list if turn detection selected a
    -- different side after the first clock sample.
    if BoardTracker.chessClubKingCaptureCompatibility then
        chessClubKingCaptures = BoardTracker.getChessClubKingCaptures(
            board,
            analysisSide
        )
        chessClubCaptureAvailable = #chessClubKingCaptures > 0
    end

    -- At the start of a standard legal turn, the opponent's king cannot already
    -- be in check. A direct Chess Club king capture is the one exception.
    if not chessClubCaptureAvailable
        and isKingInCheck(board, opposite(analysisSide)) then
        setStatus(
            "Turn/board mismatch detected — waiting for the live board to settle.",
            THEME.warning
        )
        finishAnalysisButton(generation)
        return
    end

    local detectedFen = EngineCore.boardToFen(board, analysisSide)
    screenGui:SetAttribute("Build", "FINAL_QUALITY_LOCK")
    screenGui:SetAttribute("LastBoardSource", diagnostics.source or "unknown")
    screenGui:SetAttribute("LastDetectedFEN", detectedFen)
    screenGui:SetAttribute("LastMappedPieceCount", diagnostics.mappedPieces or 0)
    print(
        "[Claude 5] Accepted board:",
        diagnostics.source or "unknown",
        "pieces:", diagnostics.mappedPieces or 0,
        "stable scans:", diagnostics.stableScans or 0,
        "FEN:", detectedFen
    )

    local positionKey = EngineCore.positionKey(tableData, board, analysisSide)
    EngineCore.activeAnalysisPositionKey = positionKey
    EngineCore.lastObservedPositionKey = positionKey
    EngineCore.pendingBoardPositionKey = EngineCore.getTableIdentity(tableData)
        .. "|"
        .. BoardTracker.pieceHash(board)
    EngineCore.pendingBoardStableScans = math.max(
        EngineCore.pendingBoardStableScans,
        EngineCore.requiredStableBoardScans
    )

    local function analysisCancelled()
        return generation ~= EngineCore.analysisGeneration
            or EngineCore.activeAnalysisPositionKey ~= positionKey
    end

    if analysisCancelled() then
        return
    end

    openingLabel.Text = "Opening: " .. detectOpening(board, analysisSide)
    updateThreatPage(board)

    local positionChanged = not lastBoard
        or boardHash(lastBoard, analysisSide) ~= boardHash(board, analysisSide)
    if positionChanged then
        hideBoardEffects()
        EngineCore.committedVisualPositionKey = nil
        EngineCore.committedVisualMoveKey = nil
    end

    screenGui:SetAttribute(
        "ChessClubKingCaptureCompatibility",
        BoardTracker.chessClubKingCaptureCompatibility
    )
    screenGui:SetAttribute(
        "LastKingCaptureOverride",
        chessClubCaptureAvailable
    )

    if chessClubCaptureAvailable then
        local kingCaptureCandidates = {}
        local winningScore = analysisSide == "white" and MATE_SCORE or -MATE_SCORE

        for index, move in ipairs(chessClubKingCaptures) do
            if index > TOP_MOVE_COUNT then
                break
            end
            move._nextBoard = applyMove(board, move)
            table.insert(kingCaptureCandidates, {
                move = move,
                score = winningScore,
                reply = nil,
                pv = { move },
                source = "Chess Club king-capture rule",
                kingCapture = true,
            })
        end

        local directSearchInfo = {
            provider = "Chess Club rules",
            depth = 0,
            nodes = 0,
            elapsed = 0,
            thinking = false,
            quick = false,
            tacticalVerified = true,
            kingCaptureOverride = true,
            visualPositionKey = positionKey,
        }

        lastAnalyzedSignature = positionKey
            .. "|CHESS_CLUB_KING_CAPTURE"
        displayCandidates(
            board,
            tableData,
            kingCaptureCandidates,
            directSearchInfo
        )
        MobileSupport.bestBadge.Text = "KING CAPTURE"
        MobileSupport.bestBadge.TextColor3 = THEME.success
        setStatus(
            "Chess Club rule detected: the enemy king can be captured now.",
            THEME.success
        )
        finishAnalysisButton(generation)
        return
    end

    analyzeButton.Text = string.upper(analysisMode) .. " SEARCHING..."
    setStatus(
        "Calculating the best " .. string.upper(analysisSide)
            .. " moves in " .. analysisMode
            .. " mode using " .. analysisPreference
            .. " • Elo Skill " .. string.upper(EngineCore.eloSkill) .. "...",
        THEME.accent2
    )

    task.wait()
    if analysisCancelled() then
        return
    end

    local quickTextShown = false

    local function showSearchProgress(progressCandidates, progressInfo)
        if analysisCancelled() then
            return
        end

        -- A valid live scan that no longer matches the analyzed position means
        -- the move has already changed. Cancel immediately so an old result can
        -- never redraw over the new board.
        local liveBoard, liveDiagnostics = BoardTracker.read2DBoard()
        if liveBoard and liveDiagnostics and liveDiagnostics.valid
            and BoardTracker.pieceHash(liveBoard)
                ~= BoardTracker.pieceHash(board) then
            EngineCore.abortActiveAnalysis(true)
            setStatus(
                "Board changed — cancelled the previous analysis.",
                THEME.warning
            )
            return
        end

        local visibleCandidates = {}
        for _, candidate in ipairs(progressCandidates or {}) do
            if candidate.move
                and candidate.move.piece
                and candidate.move.piece.color == analysisSide then
                table.insert(visibleCandidates, candidate)
            end
        end

        if #visibleCandidates == 0 then
            return
        end

        progressInfo = progressInfo or {}
        progressInfo.thinking = true

        if progressInfo.quick then
            local safeQuick, rejectedQuick, quickCancelled =
                EngineCore.filterSafetyCandidates(
                    board,
                    analysisSide,
                    visibleCandidates,
                    analysisCancelled
                )

            if quickCancelled or analysisCancelled() then
                return
            end

            screenGui:SetAttribute(
                "LastQuickRejectedCount",
                #rejectedQuick
            )

            if #safeQuick == 0 then
                analyzeButton.Text = "VERIFYING QUICK MOVE..."
                setStatus(
                    "Quick move withheld — tactical safety check is still running.",
                    THEME.warning
                )
                return
            end

            progressInfo.quickSafe = true
            quickTextShown = true

            -- Do not expose a provisional move as a playable recommendation.
            -- Users were following the QUICK row before the deeper result had
            -- finished, which made a correct later result look like a blunder.
            analyzeButton.Text = "FAST PREVIEW • VERIFYING..."
            setStatus(
                "Fast preview found; checking tactics before publishing a move.",
                THEME.warning
            )
            return
        end

        -- Completed-depth updates refresh status only. Candidate rows, arrows,
        -- and highlights stay locked until one FINAL result is published.
        local depthText = (progressInfo.depth or 0) > 0
            and (" • depth " .. tostring(progressInfo.depth))
            or ""
        local nodeText = (progressInfo.nodes or 0) > 0
            and (" • " .. tostring(progressInfo.nodes) .. " nodes")
            or ""

        analyzeButton.Text = (progressInfo.provider or "ENGINE")
            .. " THINKING..."
        setStatus(
            (progressInfo.phase or "Searching for a stronger move")
                .. depthText
                .. nodeText,
            THEME.accent2
        )
    end

    local candidates, searchInfo = searchTopMoves(
        board,
        analysisSide,
        analysisMode,
        showSearchProgress,
        analysisCancelled
    )

    if analysisCancelled() or (searchInfo and searchInfo.cancelled) then
        return
    end

    local filteredCandidates = {}
    for _, candidate in ipairs(candidates) do
        if candidate.move
            and candidate.move.piece
            and candidate.move.piece.color == analysisSide then
            table.insert(filteredCandidates, candidate)
        end
    end

    if analysisCancelled() then
        return
    end

    -- Publication gate: re-read the live board after the engine finishes. This
    -- closes the race where a late cloud/local result could be displayed after
    -- the player had already moved.
    local freshBoard, freshDiagnostics = BoardTracker.confirmBoard(tableData, board)

    if analysisCancelled() then
        return
    end

    if not freshBoard
        or not freshDiagnostics
        or freshDiagnostics.valid == false
        or freshDiagnostics.stable == false
        or BoardTracker.pieceHash(freshBoard)
            ~= BoardTracker.pieceHash(board) then
        hideBoardEffects()
        setStatus(
            "Position changed or became unstable — discarded the finished result.",
            THEME.warning
        )
        finishAnalysisButton(generation)
        return
    end

    BoardTracker.sampleClockTurn(tableData)
    local finalDetectedTurn = BoardTracker.getSideToMove(nil)
    if finalDetectedTurn and finalDetectedTurn ~= analysisSide then
        hideBoardEffects()
        setStatus(
            "Turn changed before the result finished — discarded the old suggestion.",
            THEME.warning
        )
        finishAnalysisButton(generation)
        return
    end

    board = freshBoard

    if searchInfo and searchInfo.book then
        local bookSafeCandidates, bookRejectedCandidates, bookSafetyCancelled =
            EngineCore.filterSafetyCandidates(
                board,
                analysisSide,
                filteredCandidates,
                analysisCancelled
            )

        if bookSafetyCancelled or analysisCancelled() then
            return
        end

        if #bookSafeCandidates > 0 then
            while #bookSafeCandidates > TOP_MOVE_COUNT do
                table.remove(bookSafeCandidates)
            end

            local signature = positionKey
                .. "|"
                .. analysisMode
                .. "|"
                .. analysisPreference
                .. "|"
                .. EngineCore.eloSkill
                .. "|book"
            lastAnalyzedSignature = signature

            searchInfo.visualPositionKey = positionKey
            searchInfo.thinking = false
            searchInfo.quick = false
            searchInfo.verificationDepth = 0
            searchInfo.verificationNodes = 0

            local bookRejected = bookRejectedCandidates or {}
            screenGui:SetAttribute("LastOpeningBook", searchInfo.openingName or "book")
            screenGui:SetAttribute("LastSafetyRejectedCount", #bookRejected)
            screenGui:SetAttribute(
                "LastSafetyReason",
                bookRejected[1]
                    and bookRejected[1].reason
                    or "none"
            )

            displayCandidates(board, tableData, bookSafeCandidates, searchInfo)
            setStatus(
                "Opening repertoire hit: "
                    .. (searchInfo.openingName or OpeningBook.repertoireName)
                    .. " — instant book move.",
                THEME.success
            )
            finishAnalysisButton(generation)
            return
        end

        setStatus(
            "Opening book move was rejected by safety check; using verified local fallback.",
            THEME.warning
        )
        filteredCandidates = EngineCore.fallbackRootCandidates(
            board,
            analysisSide,
            {
                deadline = os.clock() + math.min(
                    0.90,
                    math.max(0.35, ENGINE_MODES[analysisMode].timeLimit * 0.12)
                ),
                cancelCheck = analysisCancelled,
            }
        )
        searchInfo.book = false
        searchInfo.provider = "Book safety fallback"
    end

    local safeCandidates, rejectedCandidates, safetyCancelled =
        EngineCore.filterSafetyCandidates(
            board,
            analysisSide,
            filteredCandidates,
            analysisCancelled
        )

    if safetyCancelled or analysisCancelled() then
        return
    end

    -- If every returned engine candidate is invalid or allows a confirmed
    -- mate-in-one, search a wider local pool before reporting failure.
    if #safeCandidates == 0 then
        analyzeButton.Text = "RECOVERING SAFE MOVE..."
        setStatus(
            "Top engine lines failed verification — checking additional legal moves.",
            THEME.warning
        )

        local recoveryCandidates = EngineCore.fallbackRootCandidates(
            board,
            analysisSide,
            {
                deadline = os.clock() + math.min(
                    1.10,
                    math.max(0.45, ENGINE_MODES[analysisMode].timeLimit * 0.14)
                ),
                cancelCheck = analysisCancelled,
            }
        )
        local recoverySafe, recoveryRejected, recoveryCancelled =
            EngineCore.filterSafetyCandidates(
                board,
                analysisSide,
                recoveryCandidates,
                analysisCancelled
            )

        if recoveryCancelled or analysisCancelled() then
            return
        end

        for _, rejected in ipairs(recoveryRejected) do
            table.insert(rejectedCandidates, rejected)
        end

        if #recoverySafe > 0 then
            safeCandidates = recoverySafe
            searchInfo = searchInfo or {}
            searchInfo.provider = "Verified local fallback"
            searchInfo.recovered = true
        end
    end

    -- Re-search the candidate pool locally before publishing. This is the
    -- final independent guard against shallow cloud lines, static fallbacks,
    -- and short queen-winning combinations that a one-reply check can miss.
    analyzeButton.Text = "TACTICAL VERIFY..."
    setStatus(
        "Cross-checking the final candidates for short tactical blunders...",
        THEME.accent2
    )

    local verifiedCandidates, verificationInfo, verificationCancelled =
        EngineCore.verifyCandidatePool(
            board,
            analysisSide,
            safeCandidates,
            analysisMode,
            analysisCancelled
        )

    if verificationCancelled or analysisCancelled() then
        return
    end

    if verifiedCandidates and #verifiedCandidates > 0 then
        local postVerifiedSafe, postVerifiedRejected, postVerifiedCancelled =
            EngineCore.filterSafetyCandidates(
                board,
                analysisSide,
                verifiedCandidates,
                analysisCancelled
            )
        if postVerifiedCancelled or analysisCancelled() then
            return
        end
        if #postVerifiedSafe > 0 then
            safeCandidates = postVerifiedSafe
        end
        for _, rejected in ipairs(postVerifiedRejected) do
            table.insert(rejectedCandidates, rejected)
        end
    end

    searchInfo = searchInfo or {}
    searchInfo.verificationDepth = verificationInfo
        and verificationInfo.depth
        or 0
    searchInfo.verificationNodes = verificationInfo
        and verificationInfo.nodes
        or 0
    searchInfo.tacticalVerified = true
    screenGui:SetAttribute(
        "LastVerificationDepth",
        searchInfo.verificationDepth
    )
    screenGui:SetAttribute(
        "LastVerificationNodes",
        searchInfo.verificationNodes
    )

    screenGui:SetAttribute(
        "LastSafetyRejectedCount",
        #rejectedCandidates
    )
    screenGui:SetAttribute(
        "LastSafetyReason",
        rejectedCandidates[1]
            and rejectedCandidates[1].reason
            or "none"
    )

    if #safeCandidates == 0 then
        hideBoardEffects()
        clearMoveRows()
        lastCandidates = {}
        bestMoveText.Text = "-- → --"
        bestNotationText.Text = "--"
        expectedReplyText.Text = "Expected reply: --"
        setEvaluationBar(0)
        MobileSupport.bestBadge.Text = "NO VERIFIED MOVE"
        MobileSupport.bestBadge.TextColor3 = THEME.danger
        lastAnalyzedSignature = positionKey
            .. "|"
            .. analysisMode
            .. "|"
            .. analysisPreference
            .. "|"
            .. EngineCore.eloSkill
        setStatus(
            "No verified legal move was available. The position may be mate or still changing.",
            THEME.danger
        )
        finishAnalysisButton(generation)
        return
    end

    safeCandidates = EngineCore.applyEloSkill(
        board,
        analysisSide,
        safeCandidates
    )

    screenGui:SetAttribute("LastEloSkill", EngineCore.eloSkill)
    screenGui:SetAttribute(
        "LastEloMoveLoss",
        safeCandidates[1] and safeCandidates[1].eloLoss or 0
    )

    while #safeCandidates > TOP_MOVE_COUNT do
        table.remove(safeCandidates)
    end
    filteredCandidates = safeCandidates

    -- One last single-scan hash check immediately before publication prevents a
    -- move made during the safety pass from receiving stale arrows.
    local publishBoard, publishDiagnostics = BoardTracker.read2DBoard()
    if publishBoard and publishDiagnostics and publishDiagnostics.valid
        and BoardTracker.pieceHash(publishBoard)
            ~= BoardTracker.pieceHash(board) then
        hideBoardEffects()
        setStatus(
            "Board changed during verification — discarded the stale result.",
            THEME.warning
        )
        finishAnalysisButton(generation)
        return
    end

    local signature = positionKey
        .. "|"
        .. analysisMode
        .. "|"
        .. analysisPreference
        .. "|"
        .. EngineCore.eloSkill
    lastAnalyzedSignature = signature

    searchInfo = searchInfo or {}
    searchInfo.visualPositionKey = positionKey
    searchInfo.thinking = false
    searchInfo.quick = false
    displayCandidates(board, tableData, filteredCandidates, searchInfo)

    if #filteredCandidates > 0 then
        setStatus(
            string.format(
                "Table #%d • %s • %d pieces • depth %d • %d nodes • %.2fs%s",
                tableData.index,
                searchInfo.planned
                    and "Pre-planned"
                    or (searchInfo.provider
                        or (searchInfo.cloud and "Cloud" or "Local")),
                diagnostics.mappedPieces,
                tonumber(searchInfo.depth) or 0,
                tonumber(searchInfo.nodes) or 0,
                tonumber(searchInfo.elapsed) or 0,
                (searchInfo.opening and (" • " .. searchInfo.opening) or "") .. (searchInfo.gambit and (" • GAMBIT: " .. searchInfo.gambit.name) or "")
            ),
            THEME.success
        )
    else
        if isKingInCheck(board, analysisSide) then
            setStatus(string.upper(analysisSide) .. " is checkmated.", THEME.danger)
        else
            setStatus("No legal move found for " .. analysisSide .. ".", THEME.warning)
        end
    end

    finishAnalysisButton(generation)

end

local function startAnalysis() if analyzing then return end

    EngineCore.cancelPonder(true)

    EngineCore.analysisGeneration += 1
    local generation = EngineCore.analysisGeneration
    EngineCore.activeAnalysisPositionKey = nil
    analyzing = true

    task.spawn(function()
        local success, errorMessage = pcall(runAnalysis, generation)
        if not success and generation == EngineCore.analysisGeneration then
            analyzing = false
            analyzeButton.Active = true
            analyzeButton.Text = "ANALYZE NEAREST BOARD"
            setStatus("Script error: " .. tostring(errorMessage), THEME.danger)
            warn("[Claude 5]", errorMessage)
        end
    end)

end

local function toggleSelectedSide() EngineCore.abortActiveAnalysis(true)
selectedSide = selectedSide == "white" and "black" or "white"
updateSideButtons() lastAnalyzedSignature = nil lastCandidates = {}
MobileSupport.clearSuggestionWatch() clearMoveRows() hideBoardEffects()

    bestMoveText.Text = "-- → --"
    bestNotationText.Text = "--"
    expectedReplyText.Text = "Expected reply: --"
    setStatus(
        "AI locked to " .. string.upper(selectedSide) .. " moves only.",
        THEME.success
    )

    if autoEnabled then
        startAnalysis()
    end

end

local function cycleEngineMode() EngineCore.abortActiveAnalysis(false)
local currentIndex = table.find(ENGINE_MODE_ORDER, engineMode) or 2
currentIndex += 1 if currentIndex > #ENGINE_MODE_ORDER then currentIndex
= 1 end

    engineMode = ENGINE_MODE_ORDER[currentIndex]
    updateModeButtons()
    lastAnalyzedSignature = nil
    setStatus("Engine mode set to " .. engineMode .. ".", THEME.accent2)

end

local function cycleEnginePreference()
EngineCore.abortActiveAnalysis(false) local order =
EngineCore.enginePreferenceOrder local currentIndex = table.find(order,
EngineCore.enginePreference) or 1 currentIndex += 1 if currentIndex >
#order then currentIndex = 1 end

    EngineCore.enginePreference = order[currentIndex]
    updateEnginePreferenceButton()
    lastAnalyzedSignature = nil

    local description = (Claude1.STYLE_INFO[EngineCore.enginePreference] or "Claude 5")

    setStatus("Engine set to " .. description, THEME.accent2)

end

local function cycleEloSkill() EngineCore.abortActiveAnalysis(false)
local order = EngineCore.eloSkillOrder local currentIndex =
table.find(order, EngineCore.eloSkill) or 1 currentIndex += 1 if
currentIndex > #order then currentIndex = 1 end

    EngineCore.eloSkill = order[currentIndex]
    updateEloSkillButton()
    lastAnalyzedSignature = nil
    lastCandidates = {}
    lastSearchInfo = nil
    MobileSupport.clearSuggestionWatch()
    clearMoveRows()
    hideBoardEffects()

    local profile = EngineCore.eloSkillProfiles[EngineCore.eloSkill]
    local description = EngineCore.eloSkill == "Full"
        and "maximum-strength recommendations restored."
        or ("estimated " .. tostring(profile and profile.estimated or "training")
            .. " safe move selection enabled.")

    setStatus("Elo Skill set to " .. string.upper(EngineCore.eloSkill)
        .. " — " .. description, THEME.accent2)

    if autoEnabled then
        startAnalysis()
    end

end

local function toggleAuto() autoEnabled = not autoEnabled
updateAutoButtons() lastAnalyzedSignature = nil

    setStatus(
        autoEnabled and "Automatic board-change analysis enabled."
            or "Automatic analysis disabled.",
        autoEnabled and THEME.success or THEME.muted
    )

    if autoEnabled then
        startAnalysis()
    end

end

local function toggleAI() aiEnabled = not aiEnabled updateAIButton()

    if not aiEnabled then
        MobileSupport.clearSuggestionWatch()
        hideBoardEffects()
        setStatus("AI suggestions disabled.", THEME.warning)
    else
        setStatus("AI suggestions enabled.", THEME.success)
    end

end

analyzeTab.Activated:Connect(function() selectTab("Analyze") end)

threatsTab.Activated:Connect(function() selectTab("Threats") end)

settingsTab.Activated:Connect(function() selectTab("Settings") end)

analyzeButton.Activated:Connect(startAnalysis)
aiButton.Activated:Connect(toggleAI)
sideButton.Activated:Connect(toggleSelectedSide)
settingsSideButton.Activated:Connect(toggleSelectedSide)
modeButton.Activated:Connect(cycleEngineMode)
settingsModeButton.Activated:Connect(cycleEngineMode)
settingsPanel.EngineSwitch.Activated:Connect(cycleEnginePreference)

local function updateClaudeButtons()
    local panel = settingsPanel
    panel.BestOnlySwitch.Text = EngineCore.bestMoveOnly and "BEST MOVE ONLY: ON" or "BEST MOVE ONLY: OFF"
    panel.BestOnlySwitch.BackgroundColor3 = EngineCore.bestMoveOnly and THEME.success or THEME.surface2
    panel.PonderSwitch.Text = EngineCore.ponderEnabled and "PONDER: ON" or "PONDER: OFF"
    panel.PonderSwitch.BackgroundColor3 = EngineCore.ponderEnabled and THEME.success or THEME.surface2
    local premoveOn = EngineCore.premoveEnabled and EngineCore.ponderEnabled
    if not EngineCore.ponderEnabled then
        panel.PremoveSwitch.Text = "PREMOVE: needs Ponder"
    else
        panel.PremoveSwitch.Text = premoveOn and "PREMOVE: ON" or "PREMOVE: OFF"
    end
    panel.PremoveSwitch.BackgroundColor3 = premoveOn and EngineCore.PREMOVE_COLOR or THEME.surface2
    panel.PremoveSwitch.TextTransparency = EngineCore.ponderEnabled and 0 or 0.45
end

local function redisplayCandidates()
    local list = EngineCore.fullCandidates or lastCandidates
    if lastBoard and lastTableData and list and #list > 0 then
        displayCandidates(lastBoard, lastTableData, list, lastSearchInfo)
    elseif lastTableData then
        EngineCore.refreshPremoveArrow()
    end
end

settingsPanel.BestOnlySwitch.Activated:Connect(function()
    EngineCore.bestMoveOnly = not EngineCore.bestMoveOnly
    updateClaudeButtons()
    updateEffectButtons()
    redisplayCandidates()
    setStatus(
        EngineCore.bestMoveOnly and "Showing only the best move." or "Showing the top 3 moves.",
        THEME.accent2
    )
end)

settingsPanel.PonderSwitch.Activated:Connect(function()
    EngineCore.ponderEnabled = not EngineCore.ponderEnabled
    if not EngineCore.ponderEnabled then
        EngineCore.premoveEnabled = false
        EngineCore.cancelPonder(true)
    end
    updateClaudeButtons()
    setStatus(
        EngineCore.ponderEnabled and "Pondering on: Claude keeps thinking on the opponent's turn."
            or "Pondering off (premove switched off too).",
        THEME.accent2
    )
end)

settingsPanel.PremoveSwitch.Activated:Connect(function()
    if not EngineCore.ponderEnabled then
        setStatus("Turn Ponder on first - premove needs it.", THEME.warning)
        return
    end
    EngineCore.premoveEnabled = not EngineCore.premoveEnabled
    if not EngineCore.premoveEnabled then
        EngineCore.clearPremove()
    end
    updateClaudeButtons()
    setStatus(
        EngineCore.premoveEnabled and "Premove on: a red dashed arrow shows the move to prepare."
            or "Premove off.",
        THEME.accent2
    )
end)

settingsPanel.NewGameSwitch.Activated:Connect(function()
    EngineCore.cancelPonder(true)
    EngineCore.ponderPlans, EngineCore.ponderPlanOrder = {}, {}
    if not Claude1.isRunning() then
        Claude1.clearHash()
    end
    setStatus("Claude's memory cleared for a new game.", THEME.accent2)
end)

settingsPanel.CopyLogSwitch.Activated:Connect(function()
    local copied, lines = EngineCore.copyGameLog()
    if lines == 0 then
        setStatus("The game log is empty - analyse a position first.", THEME.warning)
    elseif copied then
        setStatus("Copied " .. lines .. " log lines. Paste them to get a move-by-move analysis.", THEME.success)
    else
        setStatus("Could not reach the clipboard on this device.", THEME.danger)
    end
end)

settingsPanel.ClearLogSwitch.Activated:Connect(function()
    EngineCore.gameLog, EngineCore.gameLogCount = {}, 0
    setStatus("Game log cleared.", THEME.accent2)
end)

updateClaudeButtons()
settingsPanel.EloSkillSwitch.Activated:Connect(cycleEloSkill)
settingsPanel.RankedArrowSwitch.Activated:Connect(function()
EngineCore.multiArrowEnabled = not EngineCore.multiArrowEnabled
updateEffectButtons()

    if lastCandidates[previewedCandidateIndex] and lastTableData then
        showMoveEffects(lastTableData, lastCandidates[previewedCandidateIndex].move)
        EngineCore.showRankedMoveArrows(lastTableData, lastCandidates)
    else
        hideBoardEffects()
    end

    setStatus(
        EngineCore.multiArrowEnabled
            and "Color-coded top 3 arrows enabled."
            or "Color-coded top 3 arrows disabled.",
        EngineCore.multiArrowEnabled and THEME.success or THEME.muted
    )

end) autoButton.Activated:Connect(toggleAuto)
settingsAutoButton.Activated:Connect(toggleAuto)

moveRows[1].Activated:Connect(function() previewCandidate(1) end)

moveRows[2].Activated:Connect(function() previewCandidate(2) end)

moveRows[3].Activated:Connect(function() previewCandidate(3) end)

highlightButton.Activated:Connect(function() highlightsEnabled = not
highlightsEnabled updateEffectButtons()

    if lastCandidates[previewedCandidateIndex] and lastTableData then
        showMoveEffects(lastTableData, lastCandidates[previewedCandidateIndex].move)
        EngineCore.showRankedMoveArrows(lastTableData, lastCandidates)
    else
        hideBoardEffects()
    end

end)

arrowButton.Activated:Connect(function() arrowEnabled = not arrowEnabled
updateEffectButtons()

    if lastCandidates[previewedCandidateIndex] and lastTableData then
        showMoveEffects(lastTableData, lastCandidates[previewedCandidateIndex].move)
        EngineCore.showRankedMoveArrows(lastTableData, lastCandidates)
    else
        hideBoardEffects()
    end

end)

resetPositionButton.Activated:Connect(function() resetWindowPosition()
setStatus("Window position reset.", THEME.success) end)

mainFrame:GetPropertyChangedSignal("Position"):Connect(function() end)

mainFrame.CopyLinkButton.Activated:Connect(function() if
MobileSupport.tryCopyText("https://discord.gg/VPchXhCAvt") then
mainFrame.CopyLinkButton.Text = "COPIED" setStatus("Discord link copied.", THEME.success) task.delay(1.1, function() if
mainFrame.CopyLinkButton.Parent then mainFrame.CopyLinkButton.Text =
"COPY LINK" end end) return end

    local copyBox = mainFrame:FindFirstChild("CopyLinkBox")

    if not copyBox then
        copyBox = Instance.new("TextBox")
        copyBox.Name = "CopyLinkBox"
        copyBox.Position = UDim2.new(1, -250, 0, MobileSupport.expandedFrameHeight - 48)
        copyBox.Size = UDim2.fromOffset(234, 35)
        copyBox.BackgroundColor3 = THEME.surface3
        copyBox.BorderSizePixel = 0
        copyBox.ClearTextOnFocus = false
        copyBox.MultiLine = false
        copyBox.Font = Enum.Font.GothamMedium
        copyBox.TextSize = 12
        copyBox.TextColor3 = THEME.text
        copyBox.TextXAlignment = Enum.TextXAlignment.Center
        copyBox.ZIndex = 7
        copyBox.Parent = mainFrame
        addCorner(copyBox, 10)
        addStroke(copyBox, THEME.accent2, 0.28, 1)

        copyBox.FocusLost:Connect(function()
            task.defer(function()
                if copyBox.Parent then
                    copyBox.Visible = false
                    mainFrame.CopyLinkButton.Visible = not collapsed
                    mainFrame.CopyLinkButton.Text = "COPY LINK"
                end
            end)
        end)
    end

    mainFrame.CopyLinkButton.Visible = false
    copyBox.Text = "https://discord.gg/VPchXhCAvt"
    copyBox.Visible = true
    setStatus(
        UserInputService.TouchEnabled
            and "Link selected — long-press it, then tap Copy."
            or "Link selected — press Ctrl+C to copy.",
        THEME.accent2
    )

    task.defer(function()
        if not copyBox.Parent or not copyBox.Visible then
            return
        end

        copyBox:CaptureFocus()
        copyBox.SelectionStart = 1
        copyBox.CursorPosition = #copyBox.Text + 1
    end)

end)

minimizeButton.Activated:Connect(function() setCollapsed(not collapsed)
end)

closeButton.Activated:Connect(function() setMenuVisible(false) end)

launcherButton.Activated:Connect(function() setMenuVisible(true) end)

UserInputService.InputBegan:Connect(function(input, processed) if
processed then return end

    if input.KeyCode == Enum.KeyCode.H then
        setMenuVisible(not menuVisible)
    elseif input.KeyCode == Enum.KeyCode.G then
        startAnalysis()
    end

end)

task.spawn(function() while screenGui.Parent do
task.wait(AUTO_SCAN_INTERVAL)

        MobileSupport.refreshDetectedSide(false)

        local watchActive = MobileSupport.suggestionWatchActive
            and not MobileSupport.suggestionResolved
            and not MobileSupport.staleSuggestionWarningShown
        local shouldObserve = aiEnabled
            and (autoEnabled or analyzing or watchActive or EngineCore.ponderEnabled)

        if shouldObserve then
            local tableData = findNearestChessTable()
            if tableData then
                local board, diagnostics = readBoard(tableData)
                if diagnostics and diagnostics.valid
                    and diagnostics.mappedPieces > 0
                    and hasBothKings(board) then
                    local rawPositionKey = EngineCore.getTableIdentity(tableData)
                        .. "|"
                        .. BoardTracker.pieceHash(board)

                    if rawPositionKey == EngineCore.pendingBoardPositionKey then
                        EngineCore.pendingBoardStableScans += 1
                    else
                        local previousPending = EngineCore.pendingBoardPositionKey
                        EngineCore.pendingBoardPositionKey = rawPositionKey
                        EngineCore.pendingBoardStableScans = 1
                        lastAnalyzedSignature = nil

                        if previousPending and rawPositionKey ~= previousPending then
                            if EngineCore.activeAnalysisPositionKey then
                                EngineCore.abortActiveAnalysis(true)
                            else
                                hideBoardEffects()
                            end
                            EngineCore.committedVisualPositionKey = nil
                            EngineCore.committedVisualMoveKey = nil
                            lastCandidates = {}
                            lastSearchInfo = nil
                            local pendingPremove = EngineCore.premove.uci
                            EngineCore.cancelPonder(true)
                            if pendingPremove then
                                EngineCore.revalidatePremove(pendingPremove, board, selectedSide, function(text, color)
                                    setStatus(text, color)
                                end)
                            end
                            MobileSupport.clearSuggestionWatch()
                            watchActive = false
                            setStatus(
                                "Board changed — validating the live GUI position...",
                                THEME.warning
                            )
                        end
                    end

                    local clockTurn = BoardTracker.sampleClockTurn(tableData)

                    if EngineCore.pendingBoardStableScans
                        >= EngineCore.requiredStableBoardScans then
                        BoardTracker.observeBoard(
                            board,
                            clockTurn,
                            tableData.model
                        )

                        local observedTurn = BoardTracker.getSideToMove(selectedSide)
                        local positionKey = EngineCore.positionKey(
                            tableData,
                            board,
                            observedTurn
                        )

                        if EngineCore.lastObservedPositionKey
                            and positionKey ~= EngineCore.lastObservedPositionKey then
                            EngineCore.lastObservedPositionKey = positionKey
                            lastAnalyzedSignature = nil
                        elseif not EngineCore.lastObservedPositionKey then
                            EngineCore.lastObservedPositionKey = positionKey
                        end

                        if watchActive and not analyzing then
                            MobileSupport.checkSuggestionBoardChange(board, tableData)
                        end

                        if EngineCore.ponderEnabled
                            and not analyzing
                            and BoardTracker.confirmedTurn
                            and BoardTracker.confirmedTurn ~= selectedSide then
                            EngineCore.onOpponentTurn(tableData, board, positionKey, selectedSide, engineMode)
                        elseif EngineCore.premove.move
                            and (not BoardTracker.confirmedTurn
                                or BoardTracker.confirmedTurn == selectedSide) then
                            EngineCore.clearPremove()
                        end

                        if autoEnabled
                            and not analyzing
                            and (not BoardTracker.confirmedTurn
                                or BoardTracker.confirmedTurn == selectedSide) then
                            local signature = positionKey
                                .. "|"
                                .. engineMode
                                .. "|"
                                .. EngineCore.enginePreference
                                .. "|"
                                .. EngineCore.eloSkill

                            if signature ~= lastAnalyzedSignature then
                                startAnalysis()
                            end
                        end
                    end
                end
            end
        end
    end

end)

selectTab("Analyze") updateSideButtons() updateModeButtons()
updateEnginePreferenceButton() updateEloSkillButton()
updateAutoButtons() updateAIButton() updateEffectButtons()
clearMoveRows() setEvaluationBar(0) setMenuVisible(true)

print( "[Claude 5] Ruy Lopez opening book build loaded.",
"Side:", selectedSide, "Mode:", engineMode, "Engine:",
EngineCore.enginePreference, "Elo Skill:", EngineCore.eloSkill, "H = menu, G = analyze" )
