#include "TraderAlmanac.h"

namespace wick {
namespace {

struct AlmanacRow {
    const char *yi;
    const char *ji;
    const char *yiEn;
    const char *jiEn;
    const char *lucky;
    const char *luckyEn;
    const char *sha;
    const char *shaEn;
    const char *seal;
    const char *sealEn;
};

static const AlmanacRow kWeekend[] = {
    {"合账复盘 · 享受周末", "周末焦虑 · 劳形盯盘", "Weekend review · Relax", "Weekend dread · Chart obsession", "舒适沙发 · 咖啡香气", "Cozy couch · Fresh brew", "闭门苦思 · 盯死K线", "Indoor gloom · Screen doom", "休市", "CLOSED"},
    {"户外漫游 · 拥抱自然", "无事空想 · 精神内耗", "Outdoor walk · Nature", "Idle anxiety · Overthinking", "公园林荫 · 温暖阳光", "Green park · Warm sunlight", "阴暗书房 · 反复刷推", "Dark room · Twitter doom-scroll", "踏青", "OUTDOOR"},
    {"读书烹茶 · 陪伴家人", "人在家中 · 心在盘面", "Tea & family · Be present", "Absent-minded · Market doom", "餐桌温情 · 好书一本", "Family table · Good book", "餐桌看盘 · 心不在焉", "Trading at dinner · Distraction", "修心", "ZEN"},
    {"整顿居室 · 养精蓄锐", "熬夜补课 · 乱翻研报", "Tidy up · Rest & recharge", "All-nighters · Info overload", "清爽床榻 · 充足睡眠", "Clean room · Deep sleep", "凌乱桌面 · 熬夜伤神", "Messy desk · Midnight burn", "安居", "REST"},
};
static const AlmanacRow kMacro[] = {
    {"收紧防线 · 敬畏插针", "重仓赌单 · 逆势搏弈", "Guard stops · Respect volatility", "Gambling data · Max leverage", "低倍轻仓 · 挂单离场", "Low leverage · Safe limit orders", "数据瞬间 · 市价满仓", "News spike · Market all-in", "防守", "SHIELD"},
    {"静观风云 · 待尘落定", "盲目抢跑 · 左右挨打", "Watch & wait · Let dust settle", "Front-running · Getting whipped", "空仓观望 · 喝茶静坐", "Sitting in cash · Quiet patience", "风暴中心 · 追涨杀跌", "Eye of storm · Panic chase", "静观", "WAIT"},
    {"轻仓防守 · 步步为营", "情绪上头 · 赌徒心态", "Cautious stance · Stay agile", "Emotional bets · Tilting", "严密纪律 · 独立研判", "Strict discipline · Own plan", "喊单直播间 · 冲动加倍", "Live hype streams · Revenge sizing", "守正", "GUARD"},
};
static const AlmanacRow kFriday[] = {
    {"清算减仓 · 落袋为安", "过度留仓 · 周末失眠", "Lock week's gains · Cash out", "Over-holding · Weekend dread", "落袋真金 · 周末大餐", "Realized cash · Weekend feast", "周五夜盘 · 盲目开大仓", "Late Friday · Opening heavy bags", "大吉", "LUCKY"},
    {"见好就收 · 犒劳自己", "贪胜恋战 · 利润吐尽", "Take the win · Celebrate", "Overstaying party · Giving it back", "美酒佳肴 · 惬意收官", "Good meal · Peaceful closure", "贪恋虚名 · 强行刷单", "Chasing ego · Pointless churning", "顺风", "FLOW"},
};
static const AlmanacRow kMonday[] = {
    {"通览全局 · 轻仓试水", "急功近利 · 满仓冲锋", "Plan the week · Probe small", "Impatient rush · Heavy sizing", "周线图表 · 咖啡一杯", "Weekly chart · Fresh brew", "开盘跳空 · 盲目乱追", "Opening gaps · Chasing green", "知行", "PLAN"},
    {"调准节奏 · 静候良机", "盲目开盘 · 强行寻机", "Find rhythm · Wait patiently", "Forcing trades · Impulsive start", "清晰计划 · 耐心等待", "Clear roadmap · Calm patience", "焦躁手痒 · 抢跑入场", "Itchy fingers · Rushing gates", "蓄力", "READY"},
};
static const AlmanacRow kGeneral[] = {
    {"喝冰美式 · 假装看盘", "盯一分K · 精神内耗", "Iced Americano · Chill", "1m chart doom · Overthinking", "冰美式 · 咖啡机旁", "Iced Americano · Coffee corner", "1分K线 · 精神内耗", "1m chart noise · Doom-scroll", "摸鱼", "CHILL"},
    {"合上电脑 · 出门晒晒", "躲进厕所 · 手机下单", "Touch grass · Step out", "Restroom trading · Panic check", "午后阳光 · 街角公园", "Afternoon sun · City park", "洗手间狭间 · 手机偷看", "Restroom stalls · Secret trades", "逍遥", "FREE"},
    {"物理断网 · 保持清静", "潜伏群聊 · 乱抄作业", "Go offline · Clear head", "Gossip chats · Blind copying", "静音模式 · 独立思考", "Silent phone · Own thoughts", "喊单大群 · 焦虑弹幕", "Hype group chats · Noise barrage", "清净", "PEACE"},
    {"承认好运 · 低调收钱", "赚点小钱 · 吹牛炫耀", "Humble wins · Bank it", "Bragging online · Overconfidence", "银行账户 · 提现按钮", "Bank account · Cash-out button", "朋友圈晒单 · 虚荣膨胀", "Screenshot bragging · Ego trap", "低调", "CALM"},
    {"优雅摸鱼 · 享受震荡", "手痒难耐 · 狂点鼠标", "Master idling · Enjoy chop", "Itchy fingers · Overclicking", "机械键盘 · 静音轴承", "Mechanical keys · Silent switches", "微观盘口 · 频繁刷单", "Orderbook flicker · Over-trading", "悠然", "IDLE"},
    {"吃顿好的 · 犒劳自己", "红盘吃面 · 绿盘加料", "Good dinner · Treat self", "Stress eating · Mood swings", "牛排馆 · 温暖灯光", "Steakhouse · Cozy lights", "外卖泡面 · 盯盘咀嚼", "Instant noodles · Staring at red", "犒赏", "TREAT"},
    {"卸载软件 · 睡个好觉", "凌晨三点 · 睁眼盯盘", "Sleep deep · Rest well", "3 AM panic · Chart obsession", "舒适枕头 · 深度睡眠", "Soft pillow · Deep REM sleep", "黑夜屏幕 · 刺眼蓝光", "Midnight phone · Blinding blue light", "安眠", "SLEEP"},
    {"清空自选 · 重新出发", "留恋旧爱 · 死守冷门", "Clean watchlist · Reset", "Marrying bags · Dead tickers", "全新图表 · 空白画板", "Clean chart · Fresh canvas", "亏损死仓 · 执念深陷", "Dead bags · Sunk cost trap", "归零", "RESET"},
    {"从容自若 · 坦然微笑", "怒砸键盘 · 怨天尤人", "Grace in loss · Smile", "Rage at market · Blaming others", "深呼吸 · 豁达心态", "Deep breath · Broad mindset", "桌面杂物 · 怒火攻心", "Desk clutter · Tilting rage", "从容", "SMILE"},
    {"诸事皆宜 · 顺风顺水", "自我怀疑 · 瞻前顾后", "All systems go · Smooth sail", "Self-doubt · Overhesitation", "日线共振 · 顺风主升", "Daily breakout · Green wave", "逆势摸顶 · 盲目猜空", "Fading tops · Fighting strength", "大吉", "FORTUNE"},
    {"坐等抬轿 · 让利润飞", "赚俩盒饭 · 拍断大腿", "Ride the wave · Let it run", "Tiny scalps · Early exit", "多头大均线 · 稳坐持仓", "Trend alignment · Quiet holding", "频繁出入 · 蝇头微利", "Hyper scalping · Micro gains", "坐享", "RIDE"},
    {"财运亨通 · 逢买必赚", "恐高不敢 · 踏空叹息", "Cash inflow · High luck", "FOMO fear · Missing big trends", "成交放量 · 强庄抬轿", "Volume explosion · Market breadth", "垃圾横盘 · 缩量阴跌", "Low liquidity · Bleeding chop", "亨通", "PROFIT"},
    {"躺平数钱 · 享受浮盈", "多动症犯 · 频繁翻仓", "Chill & count · Enjoy gains", "Over-fiddling · Position flipping", "长线底仓 · 浮盈加码", "Core swing · Compounding float", "左右摇摆 · 追高杀跌", "Whipsawed · Panic swapping", "顺遂", "COMPOUND"},
    {"开门见红 · 财神敲门", "斤斤计较 · 贪小失大", "Bullish dawn · Wealth arrives", "Penny pinching · Missing alpha", "大格局 · 宽阔视野", "Broad vision · Macro trend", "微小点位 · 患得患失", "Fractional ticks · Anxiety trap", "盈门", "PROSPER"},
    {"顺水行舟 · 乘风破浪", "逆水划桨 · 徒耗心力", "Flow with tide · Full sail", "Swimming upstream · Tiring out", "主线板块 · 强势龙头", "Leader sector · Strongest momentum", "弱势跟风 · 逆市硬扛", "Lagging laggards · Stubborn holding", "乘风", "MOMENTUM"},
    {"读书烹茶 · 静观云卷", "心浮气躁 · 强行寻机", "Tea & reading · Calm mind", "Restless urge · Forcing setups", "紫砂清茗 · 沉香一缕", "Hot tea · Incense smoke", "杂乱弹窗 · 频繁报警", "Noisy alerts · Constant pings", "修身", "CALM"},
    {"去健身房 · 强健体魄", "久坐伤腰 · 气血两亏", "Hit the gym · Stay active", "Desk slump · Sitting all day", "哑铃器械 · 挥汗如雨", "Free weights · Sweating it out", "久坐驼背 · 骨盆前倾", "12-hour desk chair · Poor posture", "强体", "VIGOR"},
    {"整理桌面 · 心明眼亮", "杂乱无章 · 意气用事", "Clean desk · Clear thoughts", "Messy workspace · Impulsive bias", "整洁桌面 · 护眼显示", "Clean desk · Pristine displays", "垃圾杂物 · 堆积如山", "Desk garbage · Cluttered wires", "明镜", "CLEAR"},
    {"早睡早起 · 呼吸自然", "夜战外盘 · 伤肝耗神", "Early sleep · Fresh air", "Late-night churn · Burning out", "晨曦微光 · 清新空气", "Dawn light · Crisp morning air", "通宵熬夜 · 神经衰弱", "3 AM insomnia · Red eyes", "养精", "REFRESH"},
    {"散步放空 · 澄净思绪", "连轴苦熬 · 越做越错", "Take walks · Clear head", "Endless grind · Tilting loop", "林荫小道 · 慢步慢行", "Quiet trail · Gentle stroll", "困兽之斗 · 屏幕前抓狂", "Cornered desk · Frustrated staring", "从心", "RELEASE"},
    {"弱水三千 · 只取一瓢", "贪多嚼烂 · 乱花迷眼", "One clean setup · Master it", "Chasing all · Shallow spreads", "核心战法 · 精准出击", "Signature setup · Precision hit", "全天全仓 · 样样都沾", "Over-diversified · Chasing hype", "取舍", "FOCUS"},
    {"大巧若拙 · 善守者胜", "奇技淫巧 · 迷信指标", "Pure simplicity · Good defense", "Cluttered charts · Magic indicators", "裸K价格 · 支撑阻力", "Pure Price Action · Clean levels", "花哨指标 · 自欺欺人", "15 Lagging indicators · False hope", "若拙", "SIMPLE"},
    {"避其锋芒 · 待其衰竭", "迎头硬撞 · 螳臂当车", "Dodge momentum · Wait turn", "Fighting trend · Blocking trains", "右侧衰竭 · 结构拐点", "Exhaustion print · Clean reversal", "急跌飞刀 · 盲目抄底", "Falling knives · Guessing bottoms", "避芒", "DODGE"},
    {"知行合一 · 顺应自然", "执念过重 · 逆水行舟", "Walk the talk · Follow flow", "Rigid bias · Fighting waves", "客观事实 · 敬畏盘面", "Objective facts · Chart reality", "主观臆想 · 死不认错", "Subjective wishful thinking", "知行", "ALIGN"},
    {"静如处子 · 动如脱兔", "犹豫不决 · 错失良机", "Patient wait · Swift action", "Hesitation · Missed entries", "关键点位 · 果断执行", "Key level trigger · Fast trigger", "瞻前顾后 · 追悔莫及", "Paralysis by analysis · Missed entry", "雷霆", "SWIFT"},
    {"虚怀若谷 · 敬畏无常", "盲目自大 · 傲视市场", "Humble mind · Respect market", "Hubris & ego · Defying gravity", "谦逊敬畏 · 持续进化", "Humility · Lifelong learning", "狂妄自负 · 认为必涨", "Ego explosion · Certainty illusion", "敬畏", "HUMBLE"},
    {"轻仓试盘 · 步步为营", "一把梭哈 · 搏命单车", "Probe small · Step by step", "YOLO all-in · Reckless gamble", "严格仓控 · 留足弹药", "Strict position size · Dry powder", "满仓满融 · 赌徒单注", "100x leverage · All on red", "稳健", "PRUDENT"},
    {"设好止损 · 安心离场", "心存侥幸 · 随意撤防", "Place stop · Walk away", "Wishful thinking · Moving stops", "硬止损位 · 踏实行事", "Hard stop · Peaceful heart", "撤移止损 · 祈祷反弹", "Widening stop · Praying for bounce", "严律", "DISCIPLINE"},
    {"合账复盘 · 每日一记", "亏钱装死 · 逃避真相", "Evening review · Honest journal", "Head in sand · Denying losses", "日记账本 · 诚实剖析", "Wick journal · Honest notes", "视而不见 · 盲目下注", "Ignoring mistakes · Blaming bad luck", "日省", "REVIEW"},
    {"分批建仓 · 动态防守", "顶格加杠 · 孤注一掷", "Scale in slowly · Dynamic risk", "Max leverage · One-shot bet", "分批加减 · 游刃有余", "Tranche scaling · Agility", "单点重仓 · 动弹不得", "Single entry lump-sum · Paralyzed", "有节", "RHYTHM"},
    {"顺势突破 · 确认上车", "左侧死猜 · 徒手接刀", "Confirmed break · Ride trend", "Catching falling knives", "右侧确认 · 顺水推舟", "Right-side breakout · Clean momentum", "急跌抄底 · 屡抄屡亏", "Falling knives · Constant bleeds", "破竹", "BREAK"},
};

AlmanacEntry fromRow(const AlmanacRow &row)
{
    AlmanacEntry e;
    e.yi = QString::fromUtf8(row.yi);
    e.ji = QString::fromUtf8(row.ji);
    e.yiEn = QString::fromUtf8(row.yiEn);
    e.jiEn = QString::fromUtf8(row.jiEn);
    e.seal = row.seal ? QString::fromUtf8(row.seal) : QString();
    e.sealEn = row.sealEn ? QString::fromUtf8(row.sealEn) : QString();
    e.lucky = row.lucky ? QString::fromUtf8(row.lucky) : QString();
    e.luckyEn = row.luckyEn ? QString::fromUtf8(row.luckyEn) : QString();
    e.sha = row.sha ? QString::fromUtf8(row.sha) : QString();
    e.shaEn = row.shaEn ? QString::fromUtf8(row.shaEn) : QString();
    return e;
}

template <int N>
AlmanacEntry pick(const AlmanacRow (&rows)[N], int seed)
{
    return fromRow(rows[seed % N]);
}

} // namespace

AlmanacEntry traderAlmanac(const QDate &date, bool highVolDay)
{
    const int seed = date.year() * 10000 + date.month() * 100 + date.day();
    const int weekday = date.dayOfWeek(); // 1=Mon … 7=Sun
    if (weekday == 6 || weekday == 7)
        return pick(kWeekend, seed);
    if (highVolDay)
        return pick(kMacro, seed);
    if (weekday == 5 && (seed % 3 == 0))
        return pick(kFriday, seed);
    if (weekday == 1 && (seed % 3 == 0))
        return pick(kMonday, seed);
    return pick(kGeneral, seed);
}

} // namespace wick
