import Foundation

/// Editorial company facts only; this catalog never defines market availability or live metrics.
struct TickerProfile: Decodable {
    let name: String
    let category: String
    let english: String
    let chinese: String
    let website: String
    var summary: String { BSmartLocalization.isSimplifiedChinese ? chinese : english }
    var source: URL? { URL(string: website) }

    static func lookup(_ symbol: String) -> Self? {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return profiles[key] ?? supplementalProfiles[key]
    }

    // Official-source descriptions reviewed 2026-09-07; bundled for offline availability.
    private static let supplementalProfiles: [String: Self] = {
        guard let url = Bundle.main.url(forResource: "ticker-profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([String: Self].self, from: data) else { return [:] }
        return profiles
    }()

    // Company sources reviewed 2026-09-07. Unknown symbols retain an explicit unavailable state.
    private static let profiles: [String: Self] = [
        "NVDA": Self(name: "NVIDIA", category: "Semiconductors",
            english: "NVIDIA develops accelerated computing chips, systems and software for AI, data centers and graphics.",
            chinese: "英伟达开发用于人工智能、数据中心和图形处理的加速计算芯片、系统与软件。",
            website: "https://www.nvidia.com/en-us/about-nvidia/"),
        "MSTR": Self(name: "Strategy", category: "Bitcoin treasury & software",
            english: "Strategy combines a Bitcoin treasury business with enterprise analytics software. It was previously named MicroStrategy.",
            chinese: "Strategy 经营比特币储备业务，并提供企业分析软件，前身为 MicroStrategy。",
            website: "https://www.strategy.com/company"),
        "HOOD": Self(name: "Robinhood Markets", category: "Financial services",
            english: "Robinhood provides retail brokerage, cryptocurrency and other financial services through its investing platforms.",
            chinese: "Robinhood 通过投资平台提供零售券商、加密货币及其他金融服务。",
            website: "https://robinhood.com/us/en/about-us/"),
        "PLTR": Self(name: "Palantir Technologies", category: "Enterprise software",
            english: "Palantir builds data operations and AI software for commercial and government organizations, including Foundry, Gotham, Apollo and AIP.",
            chinese: "Palantir 为企业与政府机构开发数据运营和人工智能软件，产品包括 Foundry、Gotham、Apollo 与 AIP。",
            website: "https://www.palantir.com/docs/foundry/platform-overview/overview/index.html"),
        "MU": Self(name: "Micron Technology", category: "Semiconductors",
            english: "Micron develops memory and storage products, including DRAM, NAND and NOR, for computing and other electronic systems.",
            chinese: "美光开发 DRAM、NAND 和 NOR 等内存与存储产品，应用于计算及其他电子系统。",
            website: "https://www.micron.com/about"),
        "SNDK": Self(name: "Sandisk", category: "Data storage",
            english: "Sandisk supplies flash storage products including solid-state drives, memory cards and embedded storage for consumer and enterprise uses.",
            chinese: "闪迪提供固态硬盘、存储卡和嵌入式存储等闪存产品，面向消费及企业应用。",
            website: "https://www.sandisk.com/products.aspx"),
        "TSLA": Self(name: "Tesla", category: "Vehicles & energy",
            english: "Tesla designs and manufactures electric vehicles and energy generation and storage systems.",
            chinese: "特斯拉设计和制造电动汽车，以及能源生产与储能系统。",
            website: "https://ir.tesla.com/"),
        "AMD": Self(name: "Advanced Micro Devices", category: "Semiconductors",
            english: "AMD develops high-performance and adaptive computing products for data centers, PCs, gaming and embedded systems.",
            chinese: "AMD 开发高性能与自适应计算产品，面向数据中心、个人电脑、游戏及嵌入式系统。",
            website: "https://www.amd.com/en/corporate.html"),
        "AAPL": Self(name: "Apple", category: "Consumer technology",
            english: "Apple offers iPhone, Mac, iPad and wearable devices, alongside software and digital services.",
            chinese: "苹果提供 iPhone、Mac、iPad 和可穿戴设备，以及软件与数字服务。",
            website: "https://www.apple.com/"),
        "MSFT": Self(name: "Microsoft", category: "Software & cloud",
            english: "Microsoft provides productivity software, cloud computing services and personal computing products.",
            chinese: "微软提供生产力软件、云计算服务和个人计算产品。",
            website: "https://www.microsoft.com/en-us/about"),
        "AMZN": Self(name: "Amazon", category: "Commerce & cloud",
            english: "Amazon operates online and physical stores, cloud computing through AWS, and digital media and device businesses.",
            chinese: "亚马逊经营线上与实体零售、AWS 云计算，以及数字媒体和设备业务。",
            website: "https://www.aboutamazon.com/what-we-do"),
        "ASTS": Self(name: "AST SpaceMobile", category: "Satellite communications",
            english: "AST SpaceMobile is developing a space-based cellular broadband network designed to connect directly to ordinary mobile phones.",
            chinese: "AST SpaceMobile 正在开发可直接连接普通手机的天基蜂窝宽带网络。",
            website: "https://ast-science.com/company/")
    ]
}
