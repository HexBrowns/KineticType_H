local scramble, char_class, codepoint, encode

do
    local byte, char, floor, min = string.byte, string.char, math.floor, math.min

    -- 文字のデコード（モーションの デコード::方式）の文字の扱い。obj に触らない純粋な関数だけを置く
    -- 検証器: AI/scripts/KineticType_H/verify_decode.py（この本文をそのまま luaJIT で走らせる）
    --
    -- 文字の種類（文字種を保つ・オフセットで使う）
    --   範囲で持つもの: 英大文字・英小文字・数字、その全角、ひらがな（ぁ〜ん）、カタカナ（ァ〜ヶ）、半角カタカナ（ｦ〜ﾝ）、
    --                   ギリシャ小文字、キリル大文字・小文字、漢字（U+4E00〜U+9FFF）
    --   一覧で持つもの: ギリシャ大文字（U+03A2 が欠番のため）
    --   漢字のランダムは小学 1・2 年の漢字（どの日本語フォントにもある）から選ぶ。オフセットは U+4E00〜U+9FFF の中で回す
    --   （フォントに無い字は豆腐になる）
    --   ひらがな・カタカナは JIS X 0208 の範囲だけにしてある（ゔ・ゕ・ゖ・ヷ〜ヺ・長音「ー」は対象外のまま）
    --   どれにも当たらない文字（空白・句読点・記号・ほかの文字）は入れ替えない

    local function utf8_codepoint(ch)
        local b1, b2, b3, b4 = byte(ch, 1, 4)
        if b1 == nil then
            return -1
        end
        if b1 < 0x80 then
            return b1
        end
        b2, b3, b4 = (b2 or 0x80) - 0x80, (b3 or 0x80) - 0x80, (b4 or 0x80) - 0x80
        if b1 < 0xE0 then
            return (b1 - 0xC0) * 0x40 + b2
        end
        if b1 < 0xF0 then
            return (b1 - 0xE0) * 0x1000 + b2 * 0x40 + b3
        end
        return (b1 - 0xF0) * 0x40000 + b2 * 0x1000 + b3 * 0x40 + b4
    end

    local function utf8_encode(cp)
        if cp < 0x80 then
            return char(cp)
        end
        if cp < 0x800 then
            return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
        end
        if cp < 0x10000 then
            return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
        end
        return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
            0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end

    local function split(s)
        local t = {}
        for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            t[#t + 1] = ch
        end
        return t
    end

    local KANJI = "一右雨円王音下火花貝学気九休玉金空月犬見五口校左三山子四糸字耳七車手十出女小上森人水正生青夕石赤千川先早草足村大男竹中虫町天田土二日入年白八百文木本名目立力林六"
        .. "引羽雲園遠何科夏家歌画回会海絵外角楽活間丸岩顔汽記帰弓牛魚京強教近兄形計元言原戸古午後語工公広交光考行高黄合谷国黒今才細作算"
        .. "止市矢姉思紙寺自時室社弱首秋週春書少場色食心新親図数西声星晴切雪船線前組走多太体台地池知茶昼長鳥朝直通弟店点電刀冬当東答頭同道読内南肉"
        .. "馬売買麦半番父風分聞米歩母方北毎妹万明鳴毛門夜野友用曜来里理話"
    local GREEK_UPPER = "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ"

    -- { 名前, 下端, 上端, 一覧 }（一覧があればランダムは一覧から選ぶ）
    local CLASSES = {
        { "upper", 0x41, 0x5A },
        { "lower", 0x61, 0x7A },
        { "digit", 0x30, 0x39 },
        { "fw_upper", 0xFF21, 0xFF3A },
        { "fw_lower", 0xFF41, 0xFF5A },
        { "fw_digit", 0xFF10, 0xFF19 },
        { "hira", 0x3041, 0x3093 },
        { "kata", 0x30A1, 0x30F6 },
        { "hw_kata", 0xFF66, 0xFF9D },
        { "greek_lower", 0x3B1, 0x3C9 },
        { "cyrillic_upper", 0x410, 0x42F },
        { "cyrillic_lower", 0x430, 0x44F },
        { "kanji", 0x4E00, 0x9FFF, KANJI },
        { "greek_upper", nil, nil, GREEK_UPPER },
    }

    local lists = {}

    local function list_of(cls)
        local s = cls[4]
        if s == nil then
            return nil
        end
        local t = lists[s]
        if t == nil then
            t = split(s)
            lists[s] = t
        end
        return t
    end

    local function index_in(list, ch)
        for k = 1, #list do
            if list[k] == ch then
                return k
            end
        end
        return nil
    end

    local function class_of(ch)
        local cp = utf8_codepoint(ch)
        for _, cls in ipairs(CLASSES) do
            if cls[2] ~= nil then
                if cp >= cls[2] and cp <= cls[3] then
                    return cls, cp
                end
            elseif index_in(list_of(cls), ch) then
                return cls, cp
            end
        end
        return nil, cp
    end

    -- 空白と制御文字（候補から選ぶときも入れ替えない）
    local function is_blank(cp)
        return cp < 0 or cp <= 0x20 or cp == 0x7F or (cp >= 0x80 and cp <= 0xA0) or cp == 0x1680
            or (cp >= 0x2000 and cp <= 0x200B) or cp == 0x2028 or cp == 0x2029 or cp == 0x202F
            or cp == 0x205F or cp == 0x3000 or cp == 0xFEFF
    end

    -- r（0 以上 1 未満）で 0〜n-1 の番号を選ぶ
    local function pick(n, r)
        return min(n - 1, floor(r * n))
    end

    -- scramble(元の文字, 方式, r, 候補, オフセット) → 入れ替える文字（nil は入れ替えない）
    --   方式 1 = ランダム（文字種を保つ）: 同じ種類の中から、元の文字以外を選ぶ
    --   方式 2 = ランダム（候補から）: 候補（1 文字ずつの配列）から選ぶ。空白と制御文字は入れ替えない
    --   方式 3 = オフセット: 同じ種類の中でオフセットだけずらし、端で回す（AE の「大文字小文字と数字を保持」）
    scramble = function(ch, mode, r, pool, offset)
        if type(ch) ~= "string" or ch == "" then
            return nil
        end

        if mode == 2 then
            if type(pool) ~= "table" or #pool == 0 or is_blank(utf8_codepoint(ch)) then
                return nil
            end
            return pool[pick(#pool, r) + 1]
        end

        local cls, cp = class_of(ch)
        if cls == nil then
            return nil
        end
        local list = list_of(cls)

        if mode == 1 then
            if list ~= nil then
                local own = index_in(list, ch)
                if own == nil then
                    return list[pick(#list, r) + 1]
                end
                local k = pick(#list - 1, r) + 1
                if k >= own then
                    k = k + 1
                end
                return list[k]
            end
            local n = cls[3] - cls[2] + 1
            local k = pick(n - 1, r)
            if k >= cp - cls[2] then
                k = k + 1
            end
            return utf8_encode(cls[2] + k)
        end

        if mode == 3 then
            offset = floor(offset or 0)
            if cls[2] ~= nil then
                local n = cls[3] - cls[2] + 1
                return utf8_encode(cls[2] + (cp - cls[2] + offset) % n)
            end
            local own = index_in(list, ch)
            return list[(own - 1 + offset) % #list + 1]
        end

        return nil
    end

    char_class = function(ch)
        local cls = class_of(ch)
        return cls and cls[1] or nil
    end

    codepoint = utf8_codepoint
    encode = utf8_encode
end

return {
    scramble = scramble,
    char_class = char_class,
    codepoint = codepoint,
    encode = encode,
}
