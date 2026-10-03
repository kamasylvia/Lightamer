import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LabelQueries (Plan M2-10-03 KD-1) — the FACTORY bilingual label-query
// catalog for the cosine auto-labeling (M2AI-03): ~160 photography-domain
// labels × zh/en, seeded into the `label_query` table (auditable, D-2) and
// protoyped at BUNDLE BUILD time.
//
// TWO CONSUMERS, ONE SOURCE OF TRUTH:
//   • Swift  — `seedRows(modelKey:)` feeds `SemanticStore.seedLabelQueries`
//     (the factory rows land in the user's `.lalb` where they stay
//     queryable/auditable; the PK (model_key, label, lang) makes the seed
//     idempotent).
//   • Python — `Scripts/ai-models/generate_label_prototypes.py` PARSES this
//     file (strict one-line entries, never a duplicated list) and embeds each
//     label's ENGLISH query through the pinned-revision text tower
//     (D-M2-10-CONTEXT-7: prototypes ride the model revision, die with it).
//
// DO NOT reformat the entries: one line per label, exact
// `LabelQueryEntry(label: <label>, queryZH: <zh>, queryEN: <en>),` spelling —
// the generator's parser keys on the quoted shape (this template line is
// deliberately unquoted so it never parses).
//
// The `label` key is the canonical ENGLISH name — the SAME string the
// prototype index carries and `image_label.label` stores. `queryEN` is the
// sentence the prototype is embedded from; `queryZH` is the audit/search twin
// (a zh-prototype upgrade would embed these, v2).
// ─────────────────────────────────────────────────────────────────────────────

/// One factory label: the canonical key + its bilingual query sentences.
public struct LabelQueryEntry: Sendable, Equatable {
    /// Canonical English label (== the prototype index name == `image_label.label`).
    public let label: String
    /// The Chinese retrieval sentence (label_query row, lang = "zh").
    public let queryZH: String
    /// The English retrieval sentence (label_query row, lang = "en";
    /// THE prototype source sentence per KD-1).
    public let queryEN: String

    public init(label: String, queryZH: String, queryEN: String) {
        self.label = label
        self.queryZH = queryZH
        self.queryEN = queryEN
    }
}

public enum LabelQueries {

    // MARK: - Scenes

    public static let catalog: [LabelQueryEntry] = [
        LabelQueryEntry(label: "mountain", queryZH: "一张山景的照片", queryEN: "a photo of a mountain landscape"),
        LabelQueryEntry(label: "valley", queryZH: "一张山谷的照片", queryEN: "a photo of a green valley"),
        LabelQueryEntry(label: "canyon", queryZH: "一张峡谷的照片", queryEN: "a photo of a deep canyon"),
        LabelQueryEntry(label: "cliff", queryZH: "一张悬崖的照片", queryEN: "a photo of a steep cliff"),
        LabelQueryEntry(label: "cave", queryZH: "一张洞穴的照片", queryEN: "a photo inside a cave"),
        LabelQueryEntry(label: "beach", queryZH: "一张海滩的照片", queryEN: "a photo of a sandy beach"),
        LabelQueryEntry(label: "ocean", queryZH: "一张大海的照片", queryEN: "a photo of the open ocean"),
        LabelQueryEntry(label: "lake", queryZH: "一张湖泊的照片", queryEN: "a photo of a calm lake"),
        LabelQueryEntry(label: "river", queryZH: "一条河流的照片", queryEN: "a photo of a flowing river"),
        LabelQueryEntry(label: "waterfall", queryZH: "一张瀑布的照片", queryEN: "a photo of a waterfall"),
        LabelQueryEntry(label: "island", queryZH: "一张海岛的照片", queryEN: "a photo of an island"),
        LabelQueryEntry(label: "forest", queryZH: "一张森林的照片", queryEN: "a photo of a dense forest"),
        LabelQueryEntry(label: "jungle", queryZH: "一张热带雨林的照片", queryEN: "a photo of a tropical jungle"),
        LabelQueryEntry(label: "meadow", queryZH: "一张草甸的照片", queryEN: "a photo of an open grassy meadow"),
        LabelQueryEntry(label: "flower field", queryZH: "一张花田的照片", queryEN: "a photo of a colorful flower field"),
        LabelQueryEntry(label: "desert", queryZH: "一张沙漠的照片", queryEN: "a photo of a vast desert"),
        LabelQueryEntry(label: "sand dunes", queryZH: "一张沙丘的照片", queryEN: "a photo of wind-sculpted sand dunes"),
        LabelQueryEntry(label: "snow scene", queryZH: "一张雪景的照片", queryEN: "a photo of a snowy winter scene"),
        LabelQueryEntry(label: "glacier", queryZH: "一张冰川的照片", queryEN: "a photo of a glacier"),
        LabelQueryEntry(label: "cityscape", queryZH: "一张城市景观的照片", queryEN: "a photo of a cityscape"),
        LabelQueryEntry(label: "skyline", queryZH: "一张城市天际线的照片", queryEN: "a photo of a city skyline"),
        LabelQueryEntry(label: "street", queryZH: "一张街道的照片", queryEN: "a photo of a city street"),
        LabelQueryEntry(label: "alley", queryZH: "一条小巷的照片", queryEN: "a photo of a narrow alley"),
        LabelQueryEntry(label: "indoor", queryZH: "一张室内的照片", queryEN: "a photo taken indoors"),
        LabelQueryEntry(label: "office", queryZH: "一张办公室的照片", queryEN: "a photo of an office interior"),
        LabelQueryEntry(label: "cafe", queryZH: "一张咖啡馆的照片", queryEN: "a photo inside a cozy cafe"),
        LabelQueryEntry(label: "restaurant", queryZH: "一张餐厅的照片", queryEN: "a photo inside a restaurant"),
        LabelQueryEntry(label: "kitchen", queryZH: "一张厨房的照片", queryEN: "a photo of a kitchen"),
        LabelQueryEntry(label: "bedroom", queryZH: "一张卧室的照片", queryEN: "a photo of a bedroom"),
        LabelQueryEntry(label: "living room", queryZH: "一张客厅的照片", queryEN: "a photo of a living room"),
        LabelQueryEntry(label: "studio", queryZH: "一张摄影棚的照片", queryEN: "a photo shot in a photo studio"),
        LabelQueryEntry(label: "garden", queryZH: "一张花园的照片", queryEN: "a photo of a lush garden"),
        LabelQueryEntry(label: "park", queryZH: "一张公园的照片", queryEN: "a photo of a public park"),
        LabelQueryEntry(label: "bridge", queryZH: "一张桥的照片", queryEN: "a photo of a bridge"),
        LabelQueryEntry(label: "harbor", queryZH: "一张港口的照片", queryEN: "a photo of a harbor"),
        LabelQueryEntry(label: "pier", queryZH: "一张栈桥码头的照片", queryEN: "a photo of a wooden pier"),
        LabelQueryEntry(label: "lighthouse", queryZH: "一张灯塔的照片", queryEN: "a photo of a lighthouse"),
        LabelQueryEntry(label: "countryside", queryZH: "一张乡村风景的照片", queryEN: "a photo of peaceful countryside"),
        LabelQueryEntry(label: "farm", queryZH: "一张农场的照片", queryEN: "a photo of a farm"),
        LabelQueryEntry(label: "village", queryZH: "一张村庄的照片", queryEN: "a photo of a small village"),
        LabelQueryEntry(label: "ruins", queryZH: "一张古迹遗迹的照片", queryEN: "a photo of ancient ruins"),
        LabelQueryEntry(label: "temple", queryZH: "一张寺庙的照片", queryEN: "a photo of a temple"),
        LabelQueryEntry(label: "church", queryZH: "一张教堂的照片", queryEN: "a photo of a church"),
        LabelQueryEntry(label: "castle", queryZH: "一座城堡的照片", queryEN: "a photo of a castle"),
        LabelQueryEntry(label: "skyscraper", queryZH: "一张摩天大楼的照片", queryEN: "a photo of tall skyscrapers"),
        LabelQueryEntry(label: "highway", queryZH: "一张高速公路的照片", queryEN: "a photo of a highway"),
        LabelQueryEntry(label: "railway", queryZH: "一张铁路的照片", queryEN: "a photo of a railway track"),
        LabelQueryEntry(label: "airport", queryZH: "一张机场的照片", queryEN: "a photo at an airport"),
        LabelQueryEntry(label: "rooftop", queryZH: "一张屋顶的照片", queryEN: "a photo from a rooftop"),
        LabelQueryEntry(label: "underwater", queryZH: "一张水下世界的照片", queryEN: "an underwater photo beneath the sea"),
        LabelQueryEntry(label: "aerial view", queryZH: "一张航拍俯瞰的照片", queryEN: "an aerial photo from high above"),

        // MARK: - Subjects: people

        LabelQueryEntry(label: "portrait", queryZH: "一张人物肖像照片", queryEN: "a portrait photo of a person"),
        LabelQueryEntry(label: "man", queryZH: "一张男人的照片", queryEN: "a photo of a man"),
        LabelQueryEntry(label: "woman", queryZH: "一张女人的照片", queryEN: "a photo of a woman"),
        LabelQueryEntry(label: "child", queryZH: "一张儿童的照片", queryEN: "a photo of a child"),
        LabelQueryEntry(label: "elderly person", queryZH: "一张老人的照片", queryEN: "a photo of an elderly person"),
        LabelQueryEntry(label: "couple", queryZH: "一张情侣合影的照片", queryEN: "a photo of a couple together"),
        LabelQueryEntry(label: "crowd", queryZH: "一张人群的照片", queryEN: "a photo of a crowd of people"),
        LabelQueryEntry(label: "group photo", queryZH: "一张多人合影的照片", queryEN: "a group photo of several people"),
        LabelQueryEntry(label: "selfie", queryZH: "一张自拍照", queryEN: "a selfie photo"),
        LabelQueryEntry(label: "wedding", queryZH: "一张婚礼的照片", queryEN: "a photo of a wedding ceremony"),
        LabelQueryEntry(label: "concert", queryZH: "一张演唱会现场的照片", queryEN: "a photo of a live concert"),
        LabelQueryEntry(label: "sports", queryZH: "一张体育运动的照片", queryEN: "a photo of a sports event"),
        LabelQueryEntry(label: "dancer", queryZH: "一张舞者的照片", queryEN: "a photo of a dancer performing"),
        LabelQueryEntry(label: "musician", queryZH: "一张音乐家演奏的照片", queryEN: "a photo of a musician playing"),

        // MARK: - Subjects: animals

        LabelQueryEntry(label: "cat", queryZH: "一只猫的照片", queryEN: "a photo of a cat"),
        LabelQueryEntry(label: "dog", queryZH: "一只狗的照片", queryEN: "a photo of a dog"),
        LabelQueryEntry(label: "bird", queryZH: "一只鸟的照片", queryEN: "a photo of a bird"),
        LabelQueryEntry(label: "horse", queryZH: "一匹马的照片", queryEN: "a photo of a horse"),
        LabelQueryEntry(label: "butterfly", queryZH: "一只蝴蝶的照片", queryEN: "a photo of a butterfly"),
        LabelQueryEntry(label: "insect", queryZH: "一只昆虫的照片", queryEN: "a close-up photo of an insect"),
        LabelQueryEntry(label: "fish", queryZH: "一条鱼的照片", queryEN: "a photo of a fish"),
        LabelQueryEntry(label: "wildlife", queryZH: "一张野生动物的照片", queryEN: "a wildlife photo of a wild animal"),
        LabelQueryEntry(label: "livestock", queryZH: "一张家畜的照片", queryEN: "a photo of farm livestock"),

        // MARK: - Subjects: plants & food

        LabelQueryEntry(label: "flower", queryZH: "一朵花的照片", queryEN: "a photo of a blooming flower"),
        LabelQueryEntry(label: "rose", queryZH: "一朵玫瑰的照片", queryEN: "a photo of a rose"),
        LabelQueryEntry(label: "cherry blossom", queryZH: "一张樱花的照片", queryEN: "a photo of cherry blossoms"),
        LabelQueryEntry(label: "lotus", queryZH: "一朵荷花的照片", queryEN: "a photo of a lotus flower"),
        LabelQueryEntry(label: "tree", queryZH: "一棵树的照片", queryEN: "a photo of a lone tree"),
        LabelQueryEntry(label: "leaf", queryZH: "一片树叶的照片", queryEN: "a close-up photo of a leaf"),
        LabelQueryEntry(label: "mushroom", queryZH: "一朵蘑菇的照片", queryEN: "a photo of a mushroom"),
        LabelQueryEntry(label: "food", queryZH: "一张美食的照片", queryEN: "a photo of delicious food"),
        LabelQueryEntry(label: "fruit", queryZH: "一张新鲜水果的照片", queryEN: "a photo of fresh fruit"),
        LabelQueryEntry(label: "dessert", queryZH: "一份甜点的照片", queryEN: "a photo of a sweet dessert"),
        LabelQueryEntry(label: "cake", queryZH: "一个蛋糕的照片", queryEN: "a photo of a cake"),
        LabelQueryEntry(label: "coffee", queryZH: "一杯咖啡的照片", queryEN: "a photo of a cup of coffee"),
        LabelQueryEntry(label: "tea", queryZH: "一杯茶的照片", queryEN: "a photo of a cup of tea"),
        LabelQueryEntry(label: "wine", queryZH: "一杯葡萄酒的照片", queryEN: "a photo of a glass of wine"),
        LabelQueryEntry(label: "noodles", queryZH: "一碗面条的照片", queryEN: "a photo of a bowl of noodles"),
        LabelQueryEntry(label: "sushi", queryZH: "一份寿司的照片", queryEN: "a photo of sushi"),

        // MARK: - Subjects: vehicles & structures

        LabelQueryEntry(label: "car", queryZH: "一辆汽车的照片", queryEN: "a photo of a car"),
        LabelQueryEntry(label: "sports car", queryZH: "一辆跑车的照片", queryEN: "a photo of a sleek sports car"),
        LabelQueryEntry(label: "bicycle", queryZH: "一辆自行车的照片", queryEN: "a photo of a bicycle"),
        LabelQueryEntry(label: "motorcycle", queryZH: "一辆摩托车的照片", queryEN: "a photo of a motorcycle"),
        LabelQueryEntry(label: "bus", queryZH: "一辆公共汽车的照片", queryEN: "a photo of a bus"),
        LabelQueryEntry(label: "train", queryZH: "一列火车的照片", queryEN: "a photo of a train"),
        LabelQueryEntry(label: "airplane", queryZH: "一架飞机的照片", queryEN: "a photo of an airplane"),
        LabelQueryEntry(label: "helicopter", queryZH: "一架直升机的照片", queryEN: "a photo of a helicopter"),
        LabelQueryEntry(label: "boat", queryZH: "一条小船的照片", queryEN: "a photo of a small boat"),
        LabelQueryEntry(label: "ship", queryZH: "一艘轮船的照片", queryEN: "a photo of a large ship"),
        LabelQueryEntry(label: "sailboat", queryZH: "一艘帆船的照片", queryEN: "a photo of a sailboat"),
        LabelQueryEntry(label: "hot air balloon", queryZH: "一个热气球的照片", queryEN: "a photo of a hot air balloon"),
        LabelQueryEntry(label: "kite", queryZH: "一只风筝的照片", queryEN: "a photo of a kite in the sky"),
        LabelQueryEntry(label: "building", queryZH: "一座建筑物的照片", queryEN: "a photo of a modern building"),
        LabelQueryEntry(label: "statue", queryZH: "一座雕像的照片", queryEN: "a photo of a statue"),
        LabelQueryEntry(label: "fountain", queryZH: "一座喷泉的照片", queryEN: "a photo of a fountain"),
        LabelQueryEntry(label: "clock tower", queryZH: "一座钟楼的照片", queryEN: "a photo of a clock tower"),
        LabelQueryEntry(label: "windmill", queryZH: "一座风车的照片", queryEN: "a photo of a windmill"),

        // MARK: - Light & weather & time

        LabelQueryEntry(label: "sunset", queryZH: "一张日落晚霞的照片", queryEN: "a photo of a glowing sunset"),
        LabelQueryEntry(label: "sunrise", queryZH: "一张日出的照片", queryEN: "a photo of a sunrise"),
        LabelQueryEntry(label: "night scene", queryZH: "一张夜晚的照片", queryEN: "a photo taken at night"),
        LabelQueryEntry(label: "starry sky", queryZH: "一张璀璨星空的照片", queryEN: "a photo of a starry night sky"),
        LabelQueryEntry(label: "milky way", queryZH: "一张银河的照片", queryEN: "a photo of the milky way"),
        LabelQueryEntry(label: "aurora", queryZH: "一张极光的照片", queryEN: "a photo of the aurora borealis"),
        LabelQueryEntry(label: "rainbow", queryZH: "一道彩虹的照片", queryEN: "a photo of a rainbow"),
        LabelQueryEntry(label: "fog", queryZH: "一张浓雾弥漫的照片", queryEN: "a photo shrouded in thick fog"),
        LabelQueryEntry(label: "clouds", queryZH: "一张云彩的照片", queryEN: "a photo of dramatic clouds"),
        LabelQueryEntry(label: "storm clouds", queryZH: "一张风暴乌云的照片", queryEN: "a photo of dark storm clouds"),
        LabelQueryEntry(label: "lightning", queryZH: "一道闪电的照片", queryEN: "a photo of a lightning strike"),
        LabelQueryEntry(label: "rain", queryZH: "一张雨天的照片", queryEN: "a photo taken in the rain"),
        LabelQueryEntry(label: "snowing", queryZH: "一张大雪纷飞的照片", queryEN: "a photo of falling snow"),
        LabelQueryEntry(label: "moon", queryZH: "一张月亮的照片", queryEN: "a photo of the moon in the sky"),
        LabelQueryEntry(label: "full moon", queryZH: "一轮满月的照片", queryEN: "a photo of a full moon"),
        LabelQueryEntry(label: "sunlight", queryZH: "一张阳光洒落的照片", queryEN: "a photo of warm sunlight streaming in"),
        LabelQueryEntry(label: "golden hour", queryZH: "一张黄金时刻光线的照片", queryEN: "a photo shot during golden hour"),
        LabelQueryEntry(label: "blue hour", queryZH: "一张蓝调时刻的照片", queryEN: "a photo shot during blue hour"),
        LabelQueryEntry(label: "dusk", queryZH: "一张黄昏时分的照片", queryEN: "a photo at dusk"),
        LabelQueryEntry(label: "dawn", queryZH: "一张破晓时分的照片", queryEN: "a photo at dawn"),
        LabelQueryEntry(label: "reflection", queryZH: "一张水面倒影的照片", queryEN: "a photo with mirror-like water reflections"),
        LabelQueryEntry(label: "shadow play", queryZH: "一张光影斑驳的照片", queryEN: "a photo with dramatic light and shadows"),

        // MARK: - Technique & mood

        LabelQueryEntry(label: "silhouette", queryZH: "一张剪影照片", queryEN: "a silhouette photo against bright light"),
        LabelQueryEntry(label: "close-up", queryZH: "一张特写照片", queryEN: "a close-up photo"),
        LabelQueryEntry(label: "macro", queryZH: "一张微距照片", queryEN: "an extreme macro photo of tiny details"),
        LabelQueryEntry(label: "wide angle", queryZH: "一张广角照片", queryEN: "a wide angle photo"),
        LabelQueryEntry(label: "telephoto", queryZH: "一张长焦压缩感的照片", queryEN: "a telephoto photo with compressed perspective"),
        LabelQueryEntry(label: "long exposure", queryZH: "一张长曝光照片", queryEN: "a long exposure photo with silky motion"),
        LabelQueryEntry(label: "black and white", queryZH: "一张黑白照片", queryEN: "a black and white photo"),
        LabelQueryEntry(label: "high contrast", queryZH: "一张高对比度的照片", queryEN: "a high contrast photo"),
        LabelQueryEntry(label: "low key", queryZH: "一张暗调低调的照片", queryEN: "a dark moody low key photo"),
        LabelQueryEntry(label: "high key", queryZH: "一张明亮高调的照片", queryEN: "a bright airy high key photo"),
        LabelQueryEntry(label: "warm tones", queryZH: "一张暖色调的照片", queryEN: "a photo with warm tones"),
        LabelQueryEntry(label: "cool tones", queryZH: "一张冷色调的照片", queryEN: "a photo with cool blue tones"),
        LabelQueryEntry(label: "vibrant colors", queryZH: "一张色彩浓艳的照片", queryEN: "a photo with vibrant saturated colors"),
        LabelQueryEntry(label: "pastel colors", queryZH: "一张柔和淡彩的照片", queryEN: "a photo with soft pastel colors"),
        LabelQueryEntry(label: "minimalist", queryZH: "一张极简构图的照片", queryEN: "a minimalist photo with clean composition"),
        LabelQueryEntry(label: "symmetry", queryZH: "一张对称构图的照片", queryEN: "a photo with perfect symmetry"),
        LabelQueryEntry(label: "leading lines", queryZH: "一张引导线构图的照片", queryEN: "a photo with strong leading lines"),
        LabelQueryEntry(label: "frame within frame", queryZH: "一张框架式构图的照片", queryEN: "a frame within a frame composition photo"),
        LabelQueryEntry(label: "negative space", queryZH: "一张大量留白的照片", queryEN: "a photo with vast negative space"),
        LabelQueryEntry(label: "bokeh", queryZH: "一张焦外虚化唯美的照片", queryEN: "a photo with creamy bokeh background"),
        LabelQueryEntry(label: "shallow depth of field", queryZH: "一张浅景深的照片", queryEN: "a photo with shallow depth of field"),
        LabelQueryEntry(label: "motion blur", queryZH: "一张动感模糊的照片", queryEN: "a photo with motion blur"),
        LabelQueryEntry(label: "panning", queryZH: "一张追随拍摄的照片", queryEN: "a panning shot with sharp subject and streaked background"),
        LabelQueryEntry(label: "top-down", queryZH: "一张正上方俯拍的照片", queryEN: "a top-down flat lay photo"),
        LabelQueryEntry(label: "low angle", queryZH: "一张低角度仰拍的照片", queryEN: "a photo from a low angle looking up"),
        LabelQueryEntry(label: "bird's eye view", queryZH: "一张鸟瞰全景的照片", queryEN: "a bird's eye view photo"),
        LabelQueryEntry(label: "panorama", queryZH: "一张宽幅全景的照片", queryEN: "a sweeping panorama photo"),
        LabelQueryEntry(label: "texture", queryZH: "一张突出质感的照片", queryEN: "a photo emphasizing rich texture"),
        LabelQueryEntry(label: "pattern", queryZH: "一张重复图案的照片", queryEN: "a photo of a repeating geometric pattern"),
        LabelQueryEntry(label: "abstract", queryZH: "一张抽象的照片", queryEN: "an abstract photo"),
        LabelQueryEntry(label: "still life", queryZH: "一张静物照片", queryEN: "a still life photo of arranged objects"),
        LabelQueryEntry(label: "street photography", queryZH: "一张街头抓拍的照片", queryEN: "a candid street photography shot"),
        LabelQueryEntry(label: "documentary", queryZH: "一张纪实风格的照片", queryEN: "a documentary style photo"),
        LabelQueryEntry(label: "double exposure", queryZH: "一张多重曝光的照片", queryEN: "a double exposure photo"),
        LabelQueryEntry(label: "fireworks", queryZH: "一张烟花的照片", queryEN: "a photo of fireworks bursting"),
        LabelQueryEntry(label: "campfire", queryZH: "一堆篝火的照片", queryEN: "a photo of a glowing campfire"),
        LabelQueryEntry(label: "picnic", queryZH: "一张野餐的照片", queryEN: "a photo of a picnic"),
        LabelQueryEntry(label: "hiking", queryZH: "一张徒步登山的照片", queryEN: "a photo of hikers on a trail"),
        LabelQueryEntry(label: "swimming", queryZH: "一张游泳的照片", queryEN: "a photo of someone swimming"),
        LabelQueryEntry(label: "skiing", queryZH: "一张滑雪的照片", queryEN: "a photo of skiing down a slope"),
        LabelQueryEntry(label: "surfing", queryZH: "一张冲浪的照片", queryEN: "a photo of surfing a wave"),
        LabelQueryEntry(label: "fishing", queryZH: "一张钓鱼的照片", queryEN: "a photo of fishing by the water"),
        LabelQueryEntry(label: "cycling", queryZH: "一张骑行的照片", queryEN: "a photo of cyclists riding"),
    ]

    /// The label_query seed rows for one model profile: ONE zh row + ONE en
    /// row per label (the zh/en 完整性 invariant is pinned by tests).
    public static func seedRows(modelKey: String) -> [SemanticStore.LabelQueryRow] {
        catalog.flatMap { entry in
            [
                SemanticStore.LabelQueryRow(
                    modelKey: modelKey, label: entry.label,
                    queryText: entry.queryZH, lang: "zh"),
                SemanticStore.LabelQueryRow(
                    modelKey: modelKey, label: entry.label,
                    queryText: entry.queryEN, lang: "en"),
            ]
        }
    }
}
