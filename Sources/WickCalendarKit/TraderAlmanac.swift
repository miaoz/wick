import SwiftUI
import WickSync

// MARK: - Trader Almanac Category

public enum TraderAlmanacCategory: String, Sendable, CaseIterable, Equatable {
    /// 幽默自嘲与摸鱼日常 (Humor, meme & trader lifestyle)
    case humor
    /// 财运祥瑞与顺风顺水 (Fortune & bullish blessings)
    case fortune
    /// 禅意修心与松弛生活 (Zen, mindfulness & life beyond charts)
    case zen
    /// 兵法境界与大道至简 (Market philosophy & simplicity)
    case discipline
    /// 实战避坑与温和纪律 (Craft & risk discipline)
    case contextual
}

// MARK: - Trader Almanac Entry Model

/// A concise, culturally authentic trader almanac entry:
/// - Yi (宜 / DO) & Ji (忌 / AVOID)
/// - Lucky Elements / Deities (吉神 / 贵人方)
/// - Taboo Locations / Hazards (煞位 / 避忌方)
/// - Special Seal / Stamp (特殊签条 / 方印)
public struct TraderAlmanacEntry: Sendable, Equatable, Hashable {
    public let yi: String
    public let ji: String
    public let yiEn: String
    public let jiEn: String
    public let lucky: String?
    public let luckyEn: String?
    public let sha: String?
    public let shaEn: String?
    public let seal: String?
    public let sealEn: String?
    public let category: TraderAlmanacCategory

    public init(
        yi: String,
        ji: String,
        yiEn: String,
        jiEn: String,
        lucky: String? = nil,
        luckyEn: String? = nil,
        sha: String? = nil,
        shaEn: String? = nil,
        seal: String? = nil,
        sealEn: String? = nil,
        category: TraderAlmanacCategory = .humor
    ) {
        self.yi = yi
        self.ji = ji
        self.yiEn = yiEn
        self.jiEn = jiEn
        self.lucky = lucky
        self.luckyEn = luckyEn
        self.sha = sha
        self.shaEn = shaEn
        self.seal = seal
        self.sealEn = sealEn
        self.category = category
    }

    public func yiText(language: AppLanguage) -> String {
        language == .chinese ? yi : yiEn
    }

    public func jiText(language: AppLanguage) -> String {
        language == .chinese ? ji : jiEn
    }

    public func luckyText(language: AppLanguage) -> String? {
        language == .chinese ? lucky : luckyEn
    }

    public func shaText(language: AppLanguage) -> String? {
        language == .chinese ? sha : shaEn
    }

    public func sealText(language: AppLanguage) -> String? {
        language == .chinese ? seal : sealEn
    }
}

// MARK: - Trader Almanac Engine & Rulebook

public enum TraderAlmanac: Sendable {
    
    /// Deterministically resolves the day's trader almanac entry based on date and macro environment.
    /// Strictly guarantees positive emotional value (NO "诸事不宜").
    public static func entry(for date: Date, events: [MacroCalendarEvent] = []) -> TraderAlmanacEntry {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let weekday = cal.component(.weekday, from: date) // 1 = Sun, 7 = Sat
        
        // Deterministic integer seed for this specific calendar date
        var hasher = Hasher()
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
        let seed = abs(hasher.finalize())

        // 1. Weekend Check (Sat/Sun): Relaxing, reviewing, offline life
        if weekday == 1 || weekday == 7 {
            let index = seed % weekendEntries.count
            return weekendEntries[index]
        }

        // 2. High-Impact Macro Day Check (3-star event or major macro keyword)
        let isHighVolDay = events.contains { event in
            if event.importance >= 2 { return true }
            let titleUpper = event.title.uppercased()
            return titleUpper.contains("CPI") ||
                titleUpper.contains("FOMC") ||
                titleUpper.contains("非农") ||
                titleUpper.contains("利率决议") ||
                titleUpper.contains("FED RATE") ||
                titleUpper.contains("NON-FARM") ||
                titleUpper.contains("GDP")
        }
        if isHighVolDay {
            let index = seed % macroDayEntries.count
            return macroDayEntries[index]
        }

        // 3. Friday Check: Closing the week, taking profits
        if weekday == 6 && (seed % 3 == 0) {
            let index = seed % fridayEntries.count
            return fridayEntries[index]
        }

        // 4. Monday Check: Planning the week, starting calm
        if weekday == 2 && (seed % 3 == 0) {
            let index = seed % mondayEntries.count
            return mondayEntries[index]
        }

        // 5. General Rich Pool (Humor, Fortune, Zen, Philosophy, Discipline)
        let index = seed % generalPool.count
        return generalPool[index]
    }

    // MARK: - Curated Entry Rulebook

    private static let weekendEntries: [TraderAlmanacEntry] = [
        TraderAlmanacEntry(
            yi: "合账复盘 · 享受周末",
            ji: "周末焦虑 · 劳形盯盘",
            yiEn: "Weekend review · Relax",
            jiEn: "Weekend dread · Chart obsession",
            lucky: "舒适沙发 · 咖啡香气",
            luckyEn: "Cozy couch · Fresh brew",
            sha: "闭门苦思 · 盯死K线",
            shaEn: "Indoor gloom · Screen doom",
            seal: "休市",
            sealEn: "CLOSED",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "户外漫游 · 拥抱自然",
            ji: "无事空想 · 精神内耗",
            yiEn: "Outdoor walk · Nature",
            jiEn: "Idle anxiety · Overthinking",
            lucky: "公园林荫 · 温暖阳光",
            luckyEn: "Green park · Warm sunlight",
            sha: "阴暗书房 · 反复刷推",
            shaEn: "Dark room · Twitter doom-scroll",
            seal: "踏青",
            sealEn: "OUTDOOR",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "读书烹茶 · 陪伴家人",
            ji: "人在家中 · 心在盘面",
            yiEn: "Tea & family · Be present",
            jiEn: "Absent-minded · Market doom",
            lucky: "餐桌温情 · 好书一本",
            luckyEn: "Family table · Good book",
            sha: "餐桌看盘 · 心不在焉",
            shaEn: "Trading at dinner · Distraction",
            seal: "修心",
            sealEn: "ZEN",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "整顿居室 · 养精蓄锐",
            ji: "熬夜补课 · 乱翻研报",
            yiEn: "Tidy up · Rest & recharge",
            jiEn: "All-nighters · Info overload",
            lucky: "清爽床榻 · 充足睡眠",
            luckyEn: "Clean room · Deep sleep",
            sha: "凌乱桌面 · 熬夜伤神",
            shaEn: "Messy desk · Midnight burn",
            seal: "安居",
            sealEn: "REST",
            category: .contextual
        )
    ]

    private static let macroDayEntries: [TraderAlmanacEntry] = [
        TraderAlmanacEntry(
            yi: "收紧防线 · 敬畏插针",
            ji: "重仓赌单 · 逆势搏弈",
            yiEn: "Guard stops · Respect volatility",
            jiEn: "Gambling data · Max leverage",
            lucky: "低倍轻仓 · 挂单离场",
            luckyEn: "Low leverage · Safe limit orders",
            sha: "数据瞬间 · 市价满仓",
            shaEn: "News spike · Market all-in",
            seal: "防守",
            sealEn: "SHIELD",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "静观风云 · 待尘落定",
            ji: "盲目抢跑 · 左右挨打",
            yiEn: "Watch & wait · Let dust settle",
            jiEn: "Front-running · Getting whipped",
            lucky: "空仓观望 · 喝茶静坐",
            luckyEn: "Sitting in cash · Quiet patience",
            sha: "风暴中心 · 追涨杀跌",
            shaEn: "Eye of storm · Panic chase",
            seal: "静观",
            sealEn: "WAIT",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "轻仓防守 · 步步为营",
            ji: "情绪上头 · 赌徒心态",
            yiEn: "Cautious stance · Stay agile",
            jiEn: "Emotional bets · Tilting",
            lucky: "严密纪律 · 独立研判",
            luckyEn: "Strict discipline · Own plan",
            sha: "喊单直播间 · 冲动加倍",
            shaEn: "Live hype streams · Revenge sizing",
            seal: "守正",
            sealEn: "GUARD",
            category: .contextual
        )
    ]

    private static let fridayEntries: [TraderAlmanacEntry] = [
        TraderAlmanacEntry(
            yi: "清算减仓 · 落袋为安",
            ji: "过度留仓 · 周末失眠",
            yiEn: "Lock week's gains · Cash out",
            jiEn: "Over-holding · Weekend dread",
            lucky: "落袋真金 · 周末大餐",
            luckyEn: "Realized cash · Weekend feast",
            sha: "周五夜盘 · 盲目开大仓",
            shaEn: "Late Friday · Opening heavy bags",
            seal: "大吉",
            sealEn: "LUCKY",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "见好就收 · 犒劳自己",
            ji: "贪胜恋战 · 利润吐尽",
            yiEn: "Take the win · Celebrate",
            jiEn: "Overstaying party · Giving it back",
            lucky: "美酒佳肴 · 惬意收官",
            luckyEn: "Good meal · Peaceful closure",
            sha: "贪恋虚名 · 强行刷单",
            shaEn: "Chasing ego · Pointless churning",
            seal: "顺风",
            sealEn: "FLOW",
            category: .contextual
        )
    ]

    private static let mondayEntries: [TraderAlmanacEntry] = [
        TraderAlmanacEntry(
            yi: "通览全局 · 轻仓试水",
            ji: "急功近利 · 满仓冲锋",
            yiEn: "Plan the week · Probe small",
            jiEn: "Impatient rush · Heavy sizing",
            lucky: "周线图表 · 咖啡一杯",
            luckyEn: "Weekly chart · Fresh brew",
            sha: "开盘跳空 · 盲目乱追",
            shaEn: "Opening gaps · Chasing green",
            seal: "知行",
            sealEn: "PLAN",
            category: .contextual
        ),
        TraderAlmanacEntry(
            yi: "调准节奏 · 静候良机",
            ji: "盲目开盘 · 强行寻机",
            yiEn: "Find rhythm · Wait patiently",
            jiEn: "Forcing trades · Impulsive start",
            lucky: "清晰计划 · 耐心等待",
            luckyEn: "Clear roadmap · Calm patience",
            sha: "焦躁手痒 · 抢跑入场",
            shaEn: "Itchy fingers · Rushing gates",
            seal: "蓄力",
            sealEn: "READY",
            category: .contextual
        )
    ]

    private static let generalPool: [TraderAlmanacEntry] = [
        // --- 1. 幽默自嘲与摸鱼生活 (Humor & Lifestyle) ---
        TraderAlmanacEntry(
            yi: "喝冰美式 · 假装看盘",
            ji: "盯一分K · 精神内耗",
            yiEn: "Iced Americano · Chill",
            jiEn: "1m chart doom · Overthinking",
            lucky: "冰美式 · 咖啡机旁",
            luckyEn: "Iced Americano · Coffee corner",
            sha: "1分K线 · 精神内耗",
            shaEn: "1m chart noise · Doom-scroll",
            seal: "摸鱼",
            sealEn: "CHILL",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "合上电脑 · 出门晒晒",
            ji: "躲进厕所 · 手机下单",
            yiEn: "Touch grass · Step out",
            jiEn: "Restroom trading · Panic check",
            lucky: "午后阳光 · 街角公园",
            luckyEn: "Afternoon sun · City park",
            sha: "洗手间狭间 · 手机偷看",
            shaEn: "Restroom stalls · Secret trades",
            seal: "逍遥",
            sealEn: "FREE",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "物理断网 · 保持清静",
            ji: "潜伏群聊 · 乱抄作业",
            yiEn: "Go offline · Clear head",
            jiEn: "Gossip chats · Blind copying",
            lucky: "静音模式 · 独立思考",
            luckyEn: "Silent phone · Own thoughts",
            sha: "喊单大群 · 焦虑弹幕",
            shaEn: "Hype group chats · Noise barrage",
            seal: "清净",
            sealEn: "PEACE",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "承认好运 · 低调收钱",
            ji: "赚点小钱 · 吹牛炫耀",
            yiEn: "Humble wins · Bank it",
            jiEn: "Bragging online · Overconfidence",
            lucky: "银行账户 · 提现按钮",
            luckyEn: "Bank account · Cash-out button",
            sha: "朋友圈晒单 · 虚荣膨胀",
            shaEn: "Screenshot bragging · Ego trap",
            seal: "低调",
            sealEn: "CALM",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "优雅摸鱼 · 享受震荡",
            ji: "手痒难耐 · 狂点鼠标",
            yiEn: "Master idling · Enjoy chop",
            jiEn: "Itchy fingers · Overclicking",
            lucky: "机械键盘 · 静音轴承",
            luckyEn: "Mechanical keys · Silent switches",
            sha: "微观盘口 · 频繁刷单",
            shaEn: "Orderbook flicker · Over-trading",
            seal: "悠然",
            sealEn: "IDLE",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "吃顿好的 · 犒劳自己",
            ji: "红盘吃面 · 绿盘加料",
            yiEn: "Good dinner · Treat self",
            jiEn: "Stress eating · Mood swings",
            lucky: "牛排馆 · 温暖灯光",
            luckyEn: "Steakhouse · Cozy lights",
            sha: "外卖泡面 · 盯盘咀嚼",
            shaEn: "Instant noodles · Staring at red",
            seal: "犒赏",
            sealEn: "TREAT",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "卸载软件 · 睡个好觉",
            ji: "凌晨三点 · 睁眼盯盘",
            yiEn: "Sleep deep · Rest well",
            jiEn: "3 AM panic · Chart obsession",
            lucky: "舒适枕头 · 深度睡眠",
            luckyEn: "Soft pillow · Deep REM sleep",
            sha: "黑夜屏幕 · 刺眼蓝光",
            shaEn: "Midnight phone · Blinding blue light",
            seal: "安眠",
            sealEn: "SLEEP",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "清空自选 · 重新出发",
            ji: "留恋旧爱 · 死守冷门",
            yiEn: "Clean watchlist · Reset",
            jiEn: "Marrying bags · Dead tickers",
            lucky: "全新图表 · 空白画板",
            luckyEn: "Clean chart · Fresh canvas",
            sha: "亏损死仓 · 执念深陷",
            shaEn: "Dead bags · Sunk cost trap",
            seal: "归零",
            sealEn: "RESET",
            category: .humor
        ),
        TraderAlmanacEntry(
            yi: "从容自若 · 坦然微笑",
            ji: "怒砸键盘 · 怨天尤人",
            yiEn: "Grace in loss · Smile",
            jiEn: "Rage at market · Blaming others",
            lucky: "深呼吸 · 豁达心态",
            luckyEn: "Deep breath · Broad mindset",
            sha: "桌面杂物 · 怒火攻心",
            shaEn: "Desk clutter · Tilting rage",
            seal: "从容",
            sealEn: "SMILE",
            category: .humor
        ),

        // --- 2. 财运祥瑞与顺风顺水 (Fortune & Blessings) ---
        TraderAlmanacEntry(
            yi: "诸事皆宜 · 顺风顺水",
            ji: "自我怀疑 · 瞻前顾后",
            yiEn: "All systems go · Smooth sail",
            jiEn: "Self-doubt · Overhesitation",
            lucky: "日线共振 · 顺风主升",
            luckyEn: "Daily breakout · Green wave",
            sha: "逆势摸顶 · 盲目猜空",
            shaEn: "Fading tops · Fighting strength",
            seal: "大吉",
            sealEn: "FORTUNE",
            category: .fortune
        ),
        TraderAlmanacEntry(
            yi: "坐等抬轿 · 让利润飞",
            ji: "赚俩盒饭 · 拍断大腿",
            yiEn: "Ride the wave · Let it run",
            jiEn: "Tiny scalps · Early exit",
            lucky: "多头大均线 · 稳坐持仓",
            luckyEn: "Trend alignment · Quiet holding",
            sha: "频繁出入 · 蝇头微利",
            shaEn: "Hyper scalping · Micro gains",
            seal: "坐享",
            sealEn: "RIDE",
            category: .fortune
        ),
        TraderAlmanacEntry(
            yi: "财运亨通 · 逢买必赚",
            ji: "恐高不敢 · 踏空叹息",
            yiEn: "Cash inflow · High luck",
            jiEn: "FOMO fear · Missing big trends",
            lucky: "成交放量 · 强庄抬轿",
            luckyEn: "Volume explosion · Market breadth",
            sha: "垃圾横盘 · 缩量阴跌",
            shaEn: "Low liquidity · Bleeding chop",
            seal: "亨通",
            sealEn: "PROFIT",
            category: .fortune
        ),
        TraderAlmanacEntry(
            yi: "躺平数钱 · 享受浮盈",
            ji: "多动症犯 · 频繁翻仓",
            yiEn: "Chill & count · Enjoy gains",
            jiEn: "Over-fiddling · Position flipping",
            lucky: "长线底仓 · 浮盈加码",
            luckyEn: "Core swing · Compounding float",
            sha: "左右摇摆 · 追高杀跌",
            shaEn: "Whipsawed · Panic swapping",
            seal: "顺遂",
            sealEn: "COMPOUND",
            category: .fortune
        ),
        TraderAlmanacEntry(
            yi: "开门见红 · 财神敲门",
            ji: "斤斤计较 · 贪小失大",
            yiEn: "Bullish dawn · Wealth arrives",
            jiEn: "Penny pinching · Missing alpha",
            lucky: "大格局 · 宽阔视野",
            luckyEn: "Broad vision · Macro trend",
            sha: "微小点位 · 患得患失",
            shaEn: "Fractional ticks · Anxiety trap",
            seal: "盈门",
            sealEn: "PROSPER",
            category: .fortune
        ),
        TraderAlmanacEntry(
            yi: "顺水行舟 · 乘风破浪",
            ji: "逆水划桨 · 徒耗心力",
            yiEn: "Flow with tide · Full sail",
            jiEn: "Swimming upstream · Tiring out",
            lucky: "主线板块 · 强势龙头",
            luckyEn: "Leader sector · Strongest momentum",
            sha: "弱势跟风 · 逆市硬扛",
            shaEn: "Lagging laggards · Stubborn holding",
            seal: "乘风",
            sealEn: "MOMENTUM",
            category: .fortune
        ),

        // --- 3. 禅意修心与松弛生活 (Zen & Mindfulness) ---
        TraderAlmanacEntry(
            yi: "读书烹茶 · 静观云卷",
            ji: "心浮气躁 · 强行寻机",
            yiEn: "Tea & reading · Calm mind",
            jiEn: "Restless urge · Forcing setups",
            lucky: "紫砂清茗 · 沉香一缕",
            luckyEn: "Hot tea · Incense smoke",
            sha: "杂乱弹窗 · 频繁报警",
            shaEn: "Noisy alerts · Constant pings",
            seal: "修身",
            sealEn: "CALM",
            category: .zen
        ),
        TraderAlmanacEntry(
            yi: "去健身房 · 强健体魄",
            ji: "久坐伤腰 · 气血两亏",
            yiEn: "Hit the gym · Stay active",
            jiEn: "Desk slump · Sitting all day",
            lucky: "哑铃器械 · 挥汗如雨",
            luckyEn: "Free weights · Sweating it out",
            sha: "久坐驼背 · 骨盆前倾",
            shaEn: "12-hour desk chair · Poor posture",
            seal: "强体",
            sealEn: "VIGOR",
            category: .zen
        ),
        TraderAlmanacEntry(
            yi: "整理桌面 · 心明眼亮",
            ji: "杂乱无章 · 意气用事",
            yiEn: "Clean desk · Clear thoughts",
            jiEn: "Messy workspace · Impulsive bias",
            lucky: "整洁桌面 · 护眼显示",
            luckyEn: "Clean desk · Pristine displays",
            sha: "垃圾杂物 · 堆积如山",
            shaEn: "Desk garbage · Cluttered wires",
            seal: "明镜",
            sealEn: "CLEAR",
            category: .zen
        ),
        TraderAlmanacEntry(
            yi: "早睡早起 · 呼吸自然",
            ji: "夜战外盘 · 伤肝耗神",
            yiEn: "Early sleep · Fresh air",
            jiEn: "Late-night churn · Burning out",
            lucky: "晨曦微光 · 清新空气",
            luckyEn: "Dawn light · Crisp morning air",
            sha: "通宵熬夜 · 神经衰弱",
            shaEn: "3 AM insomnia · Red eyes",
            seal: "养精",
            sealEn: "REFRESH",
            category: .zen
        ),
        TraderAlmanacEntry(
            yi: "散步放空 · 澄净思绪",
            ji: "连轴苦熬 · 越做越错",
            yiEn: "Take walks · Clear head",
            jiEn: "Endless grind · Tilting loop",
            lucky: "林荫小道 · 慢步慢行",
            luckyEn: "Quiet trail · Gentle stroll",
            sha: "困兽之斗 · 屏幕前抓狂",
            shaEn: "Cornered desk · Frustrated staring",
            seal: "从心",
            sealEn: "RELEASE",
            category: .zen
        ),

        // --- 4. 兵法境界与大道至简 (Philosophy & Wisdom) ---
        TraderAlmanacEntry(
            yi: "弱水三千 · 只取一瓢",
            ji: "贪多嚼烂 · 乱花迷眼",
            yiEn: "One clean setup · Master it",
            jiEn: "Chasing all · Shallow spreads",
            lucky: "核心战法 · 精准出击",
            luckyEn: "Signature setup · Precision hit",
            sha: "全天全仓 · 样样都沾",
            shaEn: "Over-diversified · Chasing hype",
            seal: "取舍",
            sealEn: "FOCUS",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "大巧若拙 · 善守者胜",
            ji: "奇技淫巧 · 迷信指标",
            yiEn: "Pure simplicity · Good defense",
            jiEn: "Cluttered charts · Magic indicators",
            lucky: "裸K价格 · 支撑阻力",
            luckyEn: "Pure Price Action · Clean levels",
            sha: "花哨指标 · 自欺欺人",
            shaEn: "15 Lagging indicators · False hope",
            seal: "若拙",
            sealEn: "SIMPLE",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "避其锋芒 · 待其衰竭",
            ji: "迎头硬撞 · 螳臂当车",
            yiEn: "Dodge momentum · Wait turn",
            jiEn: "Fighting trend · Blocking trains",
            lucky: "右侧衰竭 · 结构拐点",
            luckyEn: "Exhaustion print · Clean reversal",
            sha: "急跌飞刀 · 盲目抄底",
            shaEn: "Falling knives · Guessing bottoms",
            seal: "避芒",
            sealEn: "DODGE",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "知行合一 · 顺应自然",
            ji: "执念过重 · 逆水行舟",
            yiEn: "Walk the talk · Follow flow",
            jiEn: "Rigid bias · Fighting waves",
            lucky: "客观事实 · 敬畏盘面",
            luckyEn: "Objective facts · Chart reality",
            sha: "主观臆想 · 死不认错",
            shaEn: "Subjective wishful thinking",
            seal: "知行",
            sealEn: "ALIGN",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "静如处子 · 动如脱兔",
            ji: "犹豫不决 · 错失良机",
            yiEn: "Patient wait · Swift action",
            jiEn: "Hesitation · Missed entries",
            lucky: "关键点位 · 果断执行",
            luckyEn: "Key level trigger · Fast trigger",
            sha: "瞻前顾后 · 追悔莫及",
            shaEn: "Paralysis by analysis · Missed entry",
            seal: "雷霆",
            sealEn: "SWIFT",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "虚怀若谷 · 敬畏无常",
            ji: "盲目自大 · 傲视市场",
            yiEn: "Humble mind · Respect market",
            jiEn: "Hubris & ego · Defying gravity",
            lucky: "谦逊敬畏 · 持续进化",
            luckyEn: "Humility · Lifelong learning",
            sha: "狂妄自负 · 认为必涨",
            shaEn: "Ego explosion · Certainty illusion",
            seal: "敬畏",
            sealEn: "HUMBLE",
            category: .discipline
        ),

        // --- 5. 实战温和纪律与避坑 (Discipline & Edge) ---
        TraderAlmanacEntry(
            yi: "轻仓试盘 · 步步为营",
            ji: "一把梭哈 · 搏命单车",
            yiEn: "Probe small · Step by step",
            jiEn: "YOLO all-in · Reckless gamble",
            lucky: "严格仓控 · 留足弹药",
            luckyEn: "Strict position size · Dry powder",
            sha: "满仓满融 · 赌徒单注",
            shaEn: "100x leverage · All on red",
            seal: "稳健",
            sealEn: "PRUDENT",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "设好止损 · 安心离场",
            ji: "心存侥幸 · 随意撤防",
            yiEn: "Place stop · Walk away",
            jiEn: "Wishful thinking · Moving stops",
            lucky: "硬止损位 · 踏实行事",
            luckyEn: "Hard stop · Peaceful heart",
            sha: "撤移止损 · 祈祷反弹",
            shaEn: "Widening stop · Praying for bounce",
            seal: "严律",
            sealEn: "DISCIPLINE",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "合账复盘 · 每日一记",
            ji: "亏钱装死 · 逃避真相",
            yiEn: "Evening review · Honest journal",
            jiEn: "Head in sand · Denying losses",
            lucky: "日记账本 · 诚实剖析",
            luckyEn: "Wick journal · Honest notes",
            sha: "视而不见 · 盲目下注",
            shaEn: "Ignoring mistakes · Blaming bad luck",
            seal: "日省",
            sealEn: "REVIEW",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "分批建仓 · 动态防守",
            ji: "顶格加杠 · 孤注一掷",
            yiEn: "Scale in slowly · Dynamic risk",
            jiEn: "Max leverage · One-shot bet",
            lucky: "分批加减 · 游刃有余",
            luckyEn: "Tranche scaling · Agility",
            sha: "单点重仓 · 动弹不得",
            shaEn: "Single entry lump-sum · Paralyzed",
            seal: "有节",
            sealEn: "RHYTHM",
            category: .discipline
        ),
        TraderAlmanacEntry(
            yi: "顺势突破 · 确认上车",
            ji: "左侧死猜 · 徒手接刀",
            yiEn: "Confirmed break · Ride trend",
            jiEn: "Catching falling knives",
            lucky: "右侧确认 · 顺水推舟",
            luckyEn: "Right-side breakout · Clean momentum",
            sha: "急跌抄底 · 屡抄屡亏",
            shaEn: "Falling knives · Constant bleeds",
            seal: "破竹",
            sealEn: "BREAK",
            category: .discipline
        )
    ]
}

// MARK: - Shared SwiftUI Components

/// Traditional square cinnabar seal stamp (e.g. 「大吉」, 「摸鱼」, 「知行」).
public struct TraderAlmanacSealBadge: View {
    public let text: String
    public var accent: Color = TradingCalendarTheme.red
    public var scale: CGFloat = 1
    public var angle: Double = -3

    public init(text: String, accent: Color = TradingCalendarTheme.red, scale: CGFloat = 1, angle: Double = -3) {
        self.text = text
        self.accent = accent
        self.scale = scale
        self.angle = angle
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5 * scale, style: .continuous)
                .strokeBorder(accent.opacity(0.85), lineWidth: 1.2 * scale)
            Text(text)
                .font(TradingCalendarTheme.kanji(8 * scale, weight: .black))
                .foregroundStyle(accent)
                .padding(.horizontal, 3.5 * scale)
                .padding(.vertical, 1 * scale)
        }
        .fixedSize()
        .rotationEffect(.degrees(angle))
    }
}

/// A single traditional stamp chip (e.g. 「宜」/「忌」or "DO"/"AVOID") with text.
public struct TraderYiJiChip: View {
    public let mark: String
    public let text: String
    public let markBackground: Color
    public let markInk: Color
    public let textInk: Color
    public let markFont: Font
    public let textFont: Font
    public var cornerRadius: CGFloat = 2
    public var paddingH: CGFloat = 5
    public var paddingV: CGFloat = 1

    public init(
        mark: String,
        text: String,
        markBackground: Color,
        markInk: Color,
        textInk: Color,
        markFont: Font,
        textFont: Font,
        cornerRadius: CGFloat = 2,
        paddingH: CGFloat = 5,
        paddingV: CGFloat = 1
    ) {
        self.mark = mark
        self.text = text
        self.markBackground = markBackground
        self.markInk = markInk
        self.textInk = textInk
        self.markFont = markFont
        self.textFont = textFont
        self.cornerRadius = cornerRadius
        self.paddingH = paddingH
        self.paddingV = paddingV
    }

    public var body: some View {
        HStack(spacing: 5) {
            Text(mark)
                .font(markFont)
                .foregroundStyle(markInk)
                .padding(.horizontal, paddingH)
                .padding(.vertical, paddingV)
                .background(markBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            Text(text)
                .font(textFont)
                .foregroundStyle(textInk)
                .lineLimit(1)
        }
    }
}

/// A fully shared, cross-platform Yi/Ji row rendering the daily trader almanac guidance.
public struct TraderYiJiRow: View {
    public let entry: TraderAlmanacEntry
    public let language: AppLanguage
    public var yiColor: Color
    public var jiColor: Color
    public var yiInk: Color
    public var jiInk: Color
    public var textInk: Color
    public var markFont: Font
    public var textFont: Font
    public var spacing: CGFloat
    public var cornerRadius: CGFloat
    public var paddingH: CGFloat
    public var paddingV: CGFloat

    public init(
        entry: TraderAlmanacEntry,
        language: AppLanguage,
        yiColor: Color = TradingCalendarTheme.red,
        jiColor: Color = TradingCalendarTheme.ink,
        yiInk: Color = Color(red: 0.98, green: 0.92, blue: 0.85),
        jiInk: Color = Color(red: 0.98, green: 0.95, blue: 0.90),
        textInk: Color = TradingCalendarTheme.dimInk,
        markFont: Font = TradingCalendarTheme.kanji(8.5, weight: .bold),
        textFont: Font = TradingCalendarTheme.mincho(9.5),
        spacing: CGFloat = 9,
        cornerRadius: CGFloat = 2,
        paddingH: CGFloat = 5,
        paddingV: CGFloat = 1
    ) {
        self.entry = entry
        self.language = language
        self.yiColor = yiColor
        self.jiColor = jiColor
        self.yiInk = yiInk
        self.jiInk = jiInk
        self.textInk = textInk
        self.markFont = markFont
        self.textFont = textFont
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.paddingH = paddingH
        self.paddingV = paddingV
    }

    public var body: some View {
        HStack(spacing: spacing) {
            TraderYiJiChip(
                mark: language == .chinese ? "宜" : "DO",
                text: entry.yiText(language: language),
                markBackground: yiColor,
                markInk: yiInk,
                textInk: textInk,
                markFont: markFont,
                textFont: textFont,
                cornerRadius: cornerRadius,
                paddingH: paddingH,
                paddingV: paddingV
            )

            TraderYiJiChip(
                mark: language == .chinese ? "忌" : "AVOID",
                text: entry.jiText(language: language),
                markBackground: jiColor,
                markInk: jiInk,
                textInk: textInk,
                markFont: markFont,
                textFont: textFont,
                cornerRadius: cornerRadius,
                paddingH: paddingH,
                paddingV: paddingV
            )
        }
    }
}

/// A shared, elegant meta row rendering lucky deity & taboo orientation (吉神 / 煞方).
public struct TraderAlmanacMetaRow: View {
    public let entry: TraderAlmanacEntry
    public let language: AppLanguage
    public var accentColor: Color = TradingCalendarTheme.red
    public var textInk: Color = TradingCalendarTheme.dimInk
    public var font: Font = TradingCalendarTheme.mincho(8.5)

    public init(
        entry: TraderAlmanacEntry,
        language: AppLanguage,
        accentColor: Color = TradingCalendarTheme.red,
        textInk: Color = TradingCalendarTheme.dimInk,
        font: Font = TradingCalendarTheme.mincho(8.5)
    ) {
        self.entry = entry
        self.language = language
        self.accentColor = accentColor
        self.textInk = textInk
        self.font = font
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let lucky = entry.luckyText(language: language) {
                HStack(spacing: 3) {
                    Text(language == .chinese ? "吉神" : "LUCKY")
                        .font(font)
                        .foregroundStyle(accentColor)
                    Text(lucky)
                        .font(font)
                        .foregroundStyle(textInk)
                        .lineLimit(1)
                }
            }

            if entry.luckyText(language: language) != nil && entry.shaText(language: language) != nil {
                Text("·")
                    .font(font)
                    .foregroundStyle(textInk.opacity(0.5))
            }

            if let sha = entry.shaText(language: language) {
                HStack(spacing: 3) {
                    Text(language == .chinese ? "煞方" : "AVOID")
                        .font(font)
                        .foregroundStyle(textInk.opacity(0.7))
                    Text(sha)
                        .font(font)
                        .foregroundStyle(textInk)
                        .lineLimit(1)
                }
            }
        }
    }
}
