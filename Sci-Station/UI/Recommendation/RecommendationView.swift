import AppKit
import SwiftUI

struct RecommendationView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    @State private var query: String
    @State private var selectedCategories: Set<String>
    @State private var topK: Int = 10
    @State private var includeCrossList: Bool = true
    @State private var selectedAIModel: String = "deepseek-v4-flash"
    @State private var isCategorySelectorPresented = false
    @State private var isPaperSelectorPresented = false
    @State private var isHistoryManagerPresented = false
    @State private var selectedReferencePaperIDs: Set<Paper.ID> = []
    @State private var didInitializeReferencePapers = false
    @State private var didSelectDefaultHistory = false

    private static let categoryGroups: [RecommendationCategoryGroup] = [
        RecommendationCategoryGroup(
            id: "computer_science",
            title: "计算机 / Computer Science",
            systemImage: "desktopcomputer",
            options: [
                RecommendationCategoryOption(id: "cs.AI", title: "Artificial Intelligence", detail: "人工智能"),
                RecommendationCategoryOption(id: "cs.AR", title: "Hardware Architecture", detail: "硬件架构"),
                RecommendationCategoryOption(id: "cs.CC", title: "Computational Complexity", detail: "计算复杂性"),
                RecommendationCategoryOption(id: "cs.CE", title: "Computational Engineering, Finance, and Science", detail: "计算工程、金融与科学"),
                RecommendationCategoryOption(id: "cs.CG", title: "Computational Geometry", detail: "计算几何"),
                RecommendationCategoryOption(id: "cs.CL", title: "Computation and Language", detail: "自然语言处理"),
                RecommendationCategoryOption(id: "cs.CR", title: "Cryptography and Security", detail: "安全与密码学"),
                RecommendationCategoryOption(id: "cs.CV", title: "Computer Vision", detail: "计算机视觉"),
                RecommendationCategoryOption(id: "cs.CY", title: "Computers and Society", detail: "计算机与社会"),
                RecommendationCategoryOption(id: "cs.DB", title: "Databases", detail: "数据库"),
                RecommendationCategoryOption(id: "cs.DC", title: "Distributed, Parallel, and Cluster Computing", detail: "分布式、并行与集群计算"),
                RecommendationCategoryOption(id: "cs.DL", title: "Digital Libraries", detail: "数字图书馆"),
                RecommendationCategoryOption(id: "cs.DM", title: "Discrete Mathematics", detail: "离散数学"),
                RecommendationCategoryOption(id: "cs.DS", title: "Data Structures and Algorithms", detail: "数据结构与算法"),
                RecommendationCategoryOption(id: "cs.ET", title: "Emerging Technologies", detail: "新兴技术"),
                RecommendationCategoryOption(id: "cs.FL", title: "Formal Languages and Automata Theory", detail: "形式语言与自动机"),
                RecommendationCategoryOption(id: "cs.GL", title: "General Literature", detail: "综述与通用文献"),
                RecommendationCategoryOption(id: "cs.GR", title: "Graphics", detail: "图形学"),
                RecommendationCategoryOption(id: "cs.GT", title: "Computer Science and Game Theory", detail: "博弈论"),
                RecommendationCategoryOption(id: "cs.HC", title: "Human-Computer Interaction", detail: "人机交互"),
                RecommendationCategoryOption(id: "cs.IR", title: "Information Retrieval", detail: "信息检索"),
                RecommendationCategoryOption(id: "cs.IT", title: "Information Theory", detail: "信息论"),
                RecommendationCategoryOption(id: "cs.LG", title: "Machine Learning", detail: "机器学习"),
                RecommendationCategoryOption(id: "cs.LO", title: "Logic in Computer Science", detail: "计算机科学逻辑"),
                RecommendationCategoryOption(id: "cs.MA", title: "Multiagent Systems", detail: "多智能体系统"),
                RecommendationCategoryOption(id: "cs.MM", title: "Multimedia", detail: "多媒体"),
                RecommendationCategoryOption(id: "cs.MS", title: "Mathematical Software", detail: "数学软件"),
                RecommendationCategoryOption(id: "cs.NA", title: "Numerical Analysis", detail: "数值分析"),
                RecommendationCategoryOption(id: "cs.NE", title: "Neural and Evolutionary Computing", detail: "神经与进化计算"),
                RecommendationCategoryOption(id: "cs.NI", title: "Networking and Internet Architecture", detail: "网络与互联网架构"),
                RecommendationCategoryOption(id: "cs.OH", title: "Other Computer Science", detail: "其他计算机科学"),
                RecommendationCategoryOption(id: "cs.OS", title: "Operating Systems", detail: "操作系统"),
                RecommendationCategoryOption(id: "cs.PF", title: "Performance", detail: "性能"),
                RecommendationCategoryOption(id: "cs.PL", title: "Programming Languages", detail: "编程语言"),
                RecommendationCategoryOption(id: "cs.RO", title: "Robotics", detail: "机器人"),
                RecommendationCategoryOption(id: "cs.SC", title: "Symbolic Computation", detail: "符号计算"),
                RecommendationCategoryOption(id: "cs.SD", title: "Sound", detail: "声音"),
                RecommendationCategoryOption(id: "cs.SE", title: "Software Engineering", detail: "软件工程"),
                RecommendationCategoryOption(id: "cs.SI", title: "Social and Information Networks", detail: "社会与信息网络"),
                RecommendationCategoryOption(id: "cs.SY", title: "Systems and Control", detail: "系统与控制")
            ]
        ),
        RecommendationCategoryGroup(
            id: "physics",
            title: "物理 / Physics",
            systemImage: "atom",
            options: [
                RecommendationCategoryOption(id: "astro-ph.CO", title: "Cosmology and Nongalactic Astrophysics", detail: "宇宙学与非银河天体物理"),
                RecommendationCategoryOption(id: "astro-ph.EP", title: "Earth and Planetary Astrophysics", detail: "地球与行星天体物理"),
                RecommendationCategoryOption(id: "astro-ph.GA", title: "Astrophysics of Galaxies", detail: "星系天体物理"),
                RecommendationCategoryOption(id: "astro-ph.HE", title: "High Energy Astrophysical Phenomena", detail: "高能天体物理现象"),
                RecommendationCategoryOption(id: "astro-ph.IM", title: "Instrumentation and Methods for Astrophysics", detail: "天体物理仪器与方法"),
                RecommendationCategoryOption(id: "astro-ph.SR", title: "Solar and Stellar Astrophysics", detail: "太阳与恒星天体物理"),
                RecommendationCategoryOption(id: "cond-mat.dis-nn", title: "Disordered Systems and Neural Networks", detail: "无序系统与神经网络"),
                RecommendationCategoryOption(id: "cond-mat.mes-hall", title: "Mesoscale and Nanoscale Physics", detail: "介观与纳米物理"),
                RecommendationCategoryOption(id: "cond-mat.mtrl-sci", title: "Materials Science", detail: "材料科学"),
                RecommendationCategoryOption(id: "cond-mat.other", title: "Other Condensed Matter", detail: "其他凝聚态"),
                RecommendationCategoryOption(id: "cond-mat.quant-gas", title: "Quantum Gases", detail: "量子气体"),
                RecommendationCategoryOption(id: "cond-mat.soft", title: "Soft Condensed Matter", detail: "软凝聚态"),
                RecommendationCategoryOption(id: "cond-mat.stat-mech", title: "Statistical Mechanics", detail: "统计力学"),
                RecommendationCategoryOption(id: "cond-mat.str-el", title: "Strongly Correlated Electrons", detail: "强关联电子"),
                RecommendationCategoryOption(id: "cond-mat.supr-con", title: "Superconductivity", detail: "超导"),
                RecommendationCategoryOption(id: "gr-qc", title: "General Relativity and Quantum Cosmology", detail: "广义相对论与量子宇宙学"),
                RecommendationCategoryOption(id: "hep-ex", title: "High Energy Physics - Experiment", detail: "高能物理实验"),
                RecommendationCategoryOption(id: "hep-lat", title: "High Energy Physics - Lattice", detail: "高能物理格点"),
                RecommendationCategoryOption(id: "hep-ph", title: "High Energy Physics - Phenomenology", detail: "高能物理唯象"),
                RecommendationCategoryOption(id: "hep-th", title: "High Energy Physics - Theory", detail: "高能物理理论"),
                RecommendationCategoryOption(id: "math-ph", title: "Mathematical Physics", detail: "数学物理"),
                RecommendationCategoryOption(id: "nlin.AO", title: "Adaptation and Self-Organizing Systems", detail: "适应与自组织系统"),
                RecommendationCategoryOption(id: "nlin.CD", title: "Chaotic Dynamics", detail: "混沌动力学"),
                RecommendationCategoryOption(id: "nlin.CG", title: "Cellular Automata and Lattice Gases", detail: "元胞自动机与格子气"),
                RecommendationCategoryOption(id: "nlin.PS", title: "Pattern Formation and Solitons", detail: "模式形成与孤子"),
                RecommendationCategoryOption(id: "nlin.SI", title: "Exactly Solvable and Integrable Systems", detail: "可解与可积系统"),
                RecommendationCategoryOption(id: "nucl-ex", title: "Nuclear Experiment", detail: "核物理实验"),
                RecommendationCategoryOption(id: "nucl-th", title: "Nuclear Theory", detail: "核物理理论"),
                RecommendationCategoryOption(id: "physics.acc-ph", title: "Accelerator Physics", detail: "加速器物理"),
                RecommendationCategoryOption(id: "physics.ao-ph", title: "Atmospheric and Oceanic Physics", detail: "大气与海洋物理"),
                RecommendationCategoryOption(id: "physics.app-ph", title: "Applied Physics", detail: "应用物理"),
                RecommendationCategoryOption(id: "physics.atm-clus", title: "Atomic and Molecular Clusters", detail: "原子与分子团簇"),
                RecommendationCategoryOption(id: "physics.atom-ph", title: "Atomic Physics", detail: "原子物理"),
                RecommendationCategoryOption(id: "physics.bio-ph", title: "Biological Physics", detail: "生物物理"),
                RecommendationCategoryOption(id: "physics.chem-ph", title: "Chemical Physics", detail: "化学物理"),
                RecommendationCategoryOption(id: "physics.class-ph", title: "Classical Physics", detail: "经典物理"),
                RecommendationCategoryOption(id: "physics.comp-ph", title: "Computational Physics", detail: "计算物理"),
                RecommendationCategoryOption(id: "physics.data-an", title: "Data Analysis, Statistics and Probability", detail: "数据分析、统计与概率"),
                RecommendationCategoryOption(id: "physics.ed-ph", title: "Physics Education", detail: "物理教育"),
                RecommendationCategoryOption(id: "physics.flu-dyn", title: "Fluid Dynamics", detail: "流体力学"),
                RecommendationCategoryOption(id: "physics.gen-ph", title: "General Physics", detail: "普通物理"),
                RecommendationCategoryOption(id: "physics.geo-ph", title: "Geophysics", detail: "地球物理"),
                RecommendationCategoryOption(id: "physics.hist-ph", title: "History and Philosophy of Physics", detail: "物理史与物理哲学"),
                RecommendationCategoryOption(id: "physics.ins-det", title: "Instrumentation and Detectors", detail: "仪器与探测器"),
                RecommendationCategoryOption(id: "physics.med-ph", title: "Medical Physics", detail: "医学物理"),
                RecommendationCategoryOption(id: "physics.optics", title: "Optics", detail: "光学"),
                RecommendationCategoryOption(id: "physics.plasm-ph", title: "Plasma Physics", detail: "等离子体物理"),
                RecommendationCategoryOption(id: "physics.pop-ph", title: "Popular Physics", detail: "科普物理"),
                RecommendationCategoryOption(id: "physics.soc-ph", title: "Physics and Society", detail: "物理与社会"),
                RecommendationCategoryOption(id: "physics.space-ph", title: "Space Physics", detail: "空间物理"),
                RecommendationCategoryOption(id: "quant-ph", title: "Quantum Physics", detail: "量子物理")
            ]
        ),
        RecommendationCategoryGroup(
            id: "mathematics",
            title: "数学 / Mathematics",
            systemImage: "function",
            options: [
                RecommendationCategoryOption(id: "math.AG", title: "Algebraic Geometry", detail: "代数几何"),
                RecommendationCategoryOption(id: "math.AT", title: "Algebraic Topology", detail: "代数拓扑"),
                RecommendationCategoryOption(id: "math.AP", title: "Analysis of PDEs", detail: "偏微分方程"),
                RecommendationCategoryOption(id: "math.CT", title: "Category Theory", detail: "范畴论"),
                RecommendationCategoryOption(id: "math.CA", title: "Classical Analysis and ODEs", detail: "经典分析与常微分方程"),
                RecommendationCategoryOption(id: "math.CO", title: "Combinatorics", detail: "组合数学"),
                RecommendationCategoryOption(id: "math.AC", title: "Commutative Algebra", detail: "交换代数"),
                RecommendationCategoryOption(id: "math.CV", title: "Complex Variables", detail: "复变函数"),
                RecommendationCategoryOption(id: "math.DG", title: "Differential Geometry", detail: "微分几何"),
                RecommendationCategoryOption(id: "math.DS", title: "Dynamical Systems", detail: "动力系统"),
                RecommendationCategoryOption(id: "math.FA", title: "Functional Analysis", detail: "泛函分析"),
                RecommendationCategoryOption(id: "math.GM", title: "General Mathematics", detail: "一般数学"),
                RecommendationCategoryOption(id: "math.GN", title: "General Topology", detail: "一般拓扑"),
                RecommendationCategoryOption(id: "math.GT", title: "Geometric Topology", detail: "几何拓扑"),
                RecommendationCategoryOption(id: "math.GR", title: "Group Theory", detail: "群论"),
                RecommendationCategoryOption(id: "math.HO", title: "History and Overview", detail: "数学史与综述"),
                RecommendationCategoryOption(id: "math.IT", title: "Information Theory", detail: "信息论"),
                RecommendationCategoryOption(id: "math.KT", title: "K-Theory and Homology", detail: "K 理论与同调"),
                RecommendationCategoryOption(id: "math.LO", title: "Logic", detail: "逻辑"),
                RecommendationCategoryOption(id: "math.MP", title: "Mathematical Physics", detail: "数学物理"),
                RecommendationCategoryOption(id: "math.MG", title: "Metric Geometry", detail: "度量几何"),
                RecommendationCategoryOption(id: "math.NT", title: "Number Theory", detail: "数论"),
                RecommendationCategoryOption(id: "math.NA", title: "Numerical Analysis", detail: "数值分析"),
                RecommendationCategoryOption(id: "math.OA", title: "Operator Algebras", detail: "算子代数"),
                RecommendationCategoryOption(id: "math.OC", title: "Optimization and Control", detail: "优化与控制"),
                RecommendationCategoryOption(id: "math.PR", title: "Probability", detail: "概率论"),
                RecommendationCategoryOption(id: "math.QA", title: "Quantum Algebra", detail: "量子代数"),
                RecommendationCategoryOption(id: "math.RT", title: "Representation Theory", detail: "表示论"),
                RecommendationCategoryOption(id: "math.RA", title: "Rings and Algebras", detail: "环与代数"),
                RecommendationCategoryOption(id: "math.SP", title: "Spectral Theory", detail: "谱理论"),
                RecommendationCategoryOption(id: "math.ST", title: "Statistics Theory", detail: "统计理论"),
                RecommendationCategoryOption(id: "math.SG", title: "Symplectic Geometry", detail: "辛几何")
            ]
        ),
        RecommendationCategoryGroup(
            id: "statistics",
            title: "统计 / Statistics",
            systemImage: "chart.xyaxis.line",
            options: [
                RecommendationCategoryOption(id: "stat.ML", title: "Machine Learning", detail: "统计机器学习"),
                RecommendationCategoryOption(id: "stat.AP", title: "Applications", detail: "应用统计"),
                RecommendationCategoryOption(id: "stat.CO", title: "Computation", detail: "统计计算"),
                RecommendationCategoryOption(id: "stat.ME", title: "Methodology", detail: "统计方法"),
                RecommendationCategoryOption(id: "stat.OT", title: "Other Statistics", detail: "其他统计"),
                RecommendationCategoryOption(id: "stat.TH", title: "Theory", detail: "统计理论")
            ]
        ),
        RecommendationCategoryGroup(
            id: "quantitative_biology",
            title: "定量生物 / Quantitative Biology",
            systemImage: "leaf",
            options: [
                RecommendationCategoryOption(id: "q-bio.BM", title: "Biomolecules", detail: "生物分子"),
                RecommendationCategoryOption(id: "q-bio.CB", title: "Cell Behavior", detail: "细胞行为"),
                RecommendationCategoryOption(id: "q-bio.GN", title: "Genomics", detail: "基因组学"),
                RecommendationCategoryOption(id: "q-bio.MN", title: "Molecular Networks", detail: "分子网络"),
                RecommendationCategoryOption(id: "q-bio.NC", title: "Neurons and Cognition", detail: "神经与认知"),
                RecommendationCategoryOption(id: "q-bio.OT", title: "Other Quantitative Biology", detail: "其他定量生物"),
                RecommendationCategoryOption(id: "q-bio.PE", title: "Populations and Evolution", detail: "群体与进化"),
                RecommendationCategoryOption(id: "q-bio.QM", title: "Quantitative Methods", detail: "定量方法"),
                RecommendationCategoryOption(id: "q-bio.SC", title: "Subcellular Processes", detail: "亚细胞过程"),
                RecommendationCategoryOption(id: "q-bio.TO", title: "Tissues and Organs", detail: "组织与器官")
            ]
        ),
        RecommendationCategoryGroup(
            id: "eess",
            title: "电气与系统 / EESS",
            systemImage: "waveform.path.ecg",
            options: [
                RecommendationCategoryOption(id: "eess.AS", title: "Audio and Speech Processing", detail: "音频与语音处理"),
                RecommendationCategoryOption(id: "eess.IV", title: "Image and Video Processing", detail: "图像与视频处理"),
                RecommendationCategoryOption(id: "eess.SP", title: "Signal Processing", detail: "信号处理"),
                RecommendationCategoryOption(id: "eess.SY", title: "Systems and Control", detail: "系统与控制")
            ]
        ),
        RecommendationCategoryGroup(
            id: "finance_economics",
            title: "定量金融 / Quantitative Finance",
            systemImage: "banknote",
            options: [
                RecommendationCategoryOption(id: "q-fin.CP", title: "Computational Finance", detail: "计算金融"),
                RecommendationCategoryOption(id: "q-fin.EC", title: "Economics", detail: "经济金融"),
                RecommendationCategoryOption(id: "q-fin.GN", title: "General Finance", detail: "通用金融"),
                RecommendationCategoryOption(id: "q-fin.MF", title: "Mathematical Finance", detail: "数学金融"),
                RecommendationCategoryOption(id: "q-fin.PM", title: "Portfolio Management", detail: "组合管理"),
                RecommendationCategoryOption(id: "q-fin.PR", title: "Pricing of Securities", detail: "证券定价"),
                RecommendationCategoryOption(id: "q-fin.RM", title: "Risk Management", detail: "风险管理"),
                RecommendationCategoryOption(id: "q-fin.ST", title: "Statistical Finance", detail: "统计金融"),
                RecommendationCategoryOption(id: "q-fin.TR", title: "Trading and Market Microstructure", detail: "交易与市场微观结构")
            ]
        ),
        RecommendationCategoryGroup(
            id: "economics",
            title: "经济学 / Economics",
            systemImage: "chart.line.uptrend.xyaxis",
            options: [
                RecommendationCategoryOption(id: "econ.EM", title: "Econometrics", detail: "计量经济学"),
                RecommendationCategoryOption(id: "econ.GN", title: "General Economics", detail: "一般经济学"),
                RecommendationCategoryOption(id: "econ.TH", title: "Theoretical Economics", detail: "理论经济学")
            ]
        )
    ]

    private static let defaultCategoryIDs: Set<String> = ["cs.AI", "cs.CL", "cs.CV", "cs.LG"]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static var allCategoryIDs: Set<String> {
        Set(categoryGroups.flatMap(\.options).map(\.id))
    }

    init(workspace: ResearchWorkspace, project: ResearchProject) {
        self.workspace = workspace
        self.project = project
        _query = State(initialValue: "")
        _selectedCategories = State(initialValue: Self.defaultCategoryIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                controls
                Divider()
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isCategorySelectorPresented) {
            RecommendationCategorySelectorSheet(
                groups: Self.categoryGroups,
                selectedCategories: $selectedCategories,
                onDone: {
                    isCategorySelectorPresented = false
                }
            )
            .environmentObject(appModel)
        }
        .sheet(isPresented: $isPaperSelectorPresented) {
            RecommendationReferencePaperSheet(
                project: project,
                selectedPaperIDs: $selectedReferencePaperIDs,
                onDone: {
                    isPaperSelectorPresented = false
                }
            )
            .environmentObject(appModel)
        }
        .sheet(isPresented: $isHistoryManagerPresented) {
            RecommendationHistoryManagerSheet(
                onSelect: { result in
                    appModel.selectRecommendationHistory(result)
                    isHistoryManagerPresented = false
                },
                onDone: {
                    isHistoryManagerPresented = false
                }
            )
            .environmentObject(appModel)
        }
        .onAppear {
            initializeRecommendationState()
        }
        .onChange(of: selectedCategories) { _, _ in
            persistSelectedCategories()
        }
        .onChange(of: appModel.papers.map(\.id)) { _, _ in
            applyDefaultReferencePapersIfNeeded()
        }
        .onChange(of: appModel.recommendationHistory) { _, _ in
            selectTodaysRecommendationHistoryIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(appModel.localized("论文推荐", "Paper Recommendations"), systemImage: ProjectSpaceTabIcon.systemImage(for: "recommendations"))
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Button(action: refresh) {
                    if appModel.isRefreshingRecommendations || appModel.isEvaluatingRecommendationsWithAI {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(appModel.localized("推荐", "Recommend"), systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.isRefreshingRecommendations)
            }
            Text(appModel.localized(
                "AI 会先读取关键词、领域和参考论文生成 arXiv 搜索策略；推荐加入时会先进入论文库，再创建阅读 Todo。",
                "AI first reads the keywords, fields, and reference papers to plan arXiv searches; adding a recommendation saves it to Library first, then creates a reading todo."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    queryField
                    topKStepper
                    includeCrossListToggle
                    aiModelPicker
                }

                VStack(alignment: .leading, spacing: 8) {
                    queryField
                    HStack(spacing: 12) {
                        topKStepper
                        includeCrossListToggle
                        aiModelPicker
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    selectionBoxes

                    recommendationStatusBadges

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    selectionBoxes
                    recommendationStatusBadges
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var queryField: some View {
        TextField(appModel.localized("关键词，例如 diffusion planning", "Keywords, e.g. diffusion planning"), text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180, maxWidth: .infinity)
    }

    private var topKStepper: some View {
        Stepper(value: $topK, in: 1...100) {
            Text(appModel.localized("推荐 \(topK) 篇", "Recommend \(topK) papers"))
                .font(.callout.monospacedDigit())
        }
        .frame(width: 150)
    }

    private var aiModelPicker: some View {
        Picker(appModel.localized("AI 模型", "AI model"), selection: $selectedAIModel) {
            ForEach(aiModelOptions) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 170)
    }

    private var includeCrossListToggle: some View {
        Toggle(appModel.localized("包含 cross-list", "Include cross-list"), isOn: $includeCrossList)
            .toggleStyle(.switch)
            .help(appModel.localized("开启时允许论文的交叉分类命中所选领域；关闭时仅接受 primary category 命中。", "When enabled, cross-listed categories can match selected fields; when disabled, only primary category matches pass."))
            .frame(width: 160)
    }

    @ViewBuilder
    private var recommendationStatusBadges: some View {
        HStack(spacing: 12) {
            if appModel.recommendationCandidateCount > 0 {
                Label(appModel.localized("候选 \(appModel.recommendationCandidateCount) 篇", "\(appModel.recommendationCandidateCount) candidates"), systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let result = appModel.recommendationRunResult {
                Label(result.generatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectionBoxes: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                fieldsSelectionBox
                papersSelectionBox
                historySelectionBox
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldsSelectionBox
                papersSelectionBox
                historySelectionBox
            }
        }
    }

    private var fieldsSelectionBox: some View {
        compactSelectionBox(
            title: appModel.localized("领域", "Fields"),
            systemImage: "tag",
            countText: appModel.localized("\(selectedCategories.count) 项", "\(selectedCategories.count) selected"),
            detailText: selectedCategorySummary
        ) {
            isCategorySelectorPresented = true
        }
    }

    private var papersSelectionBox: some View {
        compactSelectionBox(
            title: appModel.localized("论文", "Papers"),
            systemImage: "books.vertical",
            countText: appModel.localized("\(selectedReferencePaperIDs.count) 篇", "\(selectedReferencePaperIDs.count) selected"),
            detailText: referencePaperSummaryText
        ) {
            isPaperSelectorPresented = true
        }
    }

    private var historySelectionBox: some View {
        compactSelectionBox(
            title: appModel.localized("历史", "History"),
            systemImage: "clock.arrow.circlepath",
            countText: appModel.localized("\(appModel.recommendationHistory.count) 条", "\(appModel.recommendationHistory.count) runs"),
            detailText: recommendationHistorySummaryText
        ) {
            isHistoryManagerPresented = true
        }
    }

    private func compactSelectionBox(title: String, systemImage: String, countText: String, detailText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(countText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, idealWidth: 180, maxWidth: 220, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let error = appModel.recommendationErrorMessage, !error.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(appModel.localized("推荐刷新失败", "Recommendation refresh failed"), systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(action: refresh) {
                    Label(appModel.localized("重试", "Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 20)
        } else {
            resultsColumn
        }
    }

    private var resultsColumn: some View {
        resultsPane
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 14)
    }

    @ViewBuilder
    private var resultsPane: some View {
        if let result = appModel.recommendationRunResult, !result.scores.isEmpty {
            let sortedScores = sortedRecommendationScores(result.scores)
            LazyVStack(alignment: .leading, spacing: 12) {
                resultSummary(result)
                ForEach(Array(sortedScores.enumerated()), id: \.element.id) { index, score in
                    RecommendationScoreRow(
                        score: score,
                        displayRank: index + 1,
                        scope: selectedScope,
                        aiComment: aiComment(for: score, evaluation: result.aiEvaluation),
                        aiReview: aiReview(for: score, evaluation: result.aiEvaluation),
                        feedback: appModel.recommendationFeedbackType(for: score),
                        onAddToLibrary: {
                            appModel.addRecommendationToLibrary(score, scope: selectedScope)
                        },
                        onAddReadingTodo: {
                            appModel.addRecommendationToReadingTodo(score, scope: selectedScope)
                        },
                        onFeedback: { type in
                            appModel.recordRecommendationFeedback(type, for: score, scope: selectedScope)
                        },
                        onOpenReading: {
                            appModel.openRecommendationReadingTodo()
                        },
                        isInLibrary: appModel.isRecommendationInLibrary(score),
                        isInReadingTodo: appModel.isRecommendationInReadingList(score, scope: selectedScope),
                        isAddingToLibrary: appModel.isAddingRecommendationToLibrary(score),
                        isAddingReadingTodo: appModel.isAddingRecommendationToReadingTodo(score)
                    )
                }
            }
            .padding(.vertical, 2)
        } else if let result = appModel.recommendationRunResult {
            zeroRecommendationState(result)
        } else {
            emptyRecommendationState
        }
    }

    private func sortedRecommendationScores(_ scores: [RecommendationScore]) -> [RecommendationScore] {
        scores.sorted { lhs, rhs in
            if lhs.total != rhs.total {
                return lhs.total > rhs.total
            }
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.candidate.displayTitle.localizedStandardCompare(rhs.candidate.displayTitle) == .orderedAscending
        }
    }

    private func zeroRecommendationState(_ result: RecommendationRunResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(appModel.localized("本次没有可显示推荐", "No displayable recommendations"), systemImage: "exclamationmark.magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(result.sourceNote ?? appModel.localized("arXiv 未返回候选论文。", "arXiv returned no candidates."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Text(appModel.localized("候选：\(result.candidateCount) 篇；推荐：\(result.scores.count) 篇", "\(result.candidateCount) candidates; \(result.scores.count) recommendations"))
                Text(appModel.localized("关键词：\(result.query.isEmpty ? "（空）" : result.query)", "Query: \(result.query.isEmpty ? "(empty)" : result.query)"))
                Text(appModel.localized("领域：\(result.categories.prefix(10).joined(separator: " · "))", "Fields: \(result.categories.prefix(10).joined(separator: " · "))"))
                Text(appModel.localized("Cross-list：\(result.includeCrossList ? "包含" : "仅 Primary")", "Cross-list: \(result.includeCrossList ? "included" : "primary only")"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            HStack(spacing: 10) {
                Button(action: refresh) {
                    Label(appModel.localized("重试", "Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.isRefreshingRecommendations)
                Button {
                    query = ""
                    refresh()
                } label: {
                    Label(appModel.localized("清空关键词后重试", "Retry without keywords"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(appModel.isRefreshingRecommendations || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyRecommendationState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appModel.localized("还没有 AI/arXiv 推荐", "No AI/arXiv recommendations yet"), systemImage: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(appModel.localized("选择领域、关键词和参考论文后点击推荐。AI 会先生成搜索策略，再由 arXiv 返回候选论文。", "Choose fields, keywords, and reference papers, then recommend. AI first plans the searches, then arXiv returns candidate papers."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: refresh) {
                Label(appModel.localized("获取推荐", "Fetch Recommendations"), systemImage: "arrow.down.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.isRefreshingRecommendations)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func resultSummary(_ result: RecommendationRunResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(result.sourceNote ?? appModel.localized("arXiv 推荐", "arXiv recommendations"), systemImage: "calendar.badge.clock")
                if let sourceDate = result.sourceDate {
                    Text(Self.dayFormatter.string(from: sourceDate))
                }
                Text(result.includeCrossList ? appModel.localized("含 cross-list", "cross-list on") : appModel.localized("仅 primary", "primary only"))
                Spacer(minLength: 0)
                Text(appModel.localized("共 \(result.scores.count) 篇", "\(result.scores.count) papers"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if appModel.isEvaluatingRecommendationsWithAI {
                Label(appModel.localized("AI 正在阅读标题和摘要并生成评价…", "AI is reading titles and abstracts for evaluation…"), systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status = appModel.recommendationAIEvaluationStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedScope: RecommendationTarget {
        .project(project.id)
    }

    private func refresh() {
        appModel.refreshArxivRecommendations(project: project, query: query, categories: parsedCategories, topK: topK, includeCrossList: includeCrossList, aiModel: selectedAIModel, referencePaperIDs: selectedReferencePaperIDs)
    }

    private var parsedCategories: [String] {
        Self.categoryGroups
            .flatMap(\.options)
            .map(\.id)
            .filter { selectedCategories.contains($0) }
    }

    private var aiModelOptions: [DeepSeekModelOption] {
        DeepSeekModelOption.presets.filter { option in
            option.id == "deepseek-v4-flash" || option.id == "deepseek-v4-pro"
        }
    }

    private func aiComment(for score: RecommendationScore, evaluation: RecommendationAIEvaluation?) -> String? {
        guard let evaluation else {
            return nil
        }
        let aliases = aiAliases(for: score)
        if let existing = aliases.compactMap({ evaluation.commentsByScoreID[$0]?.recommendationNonEmptyText }).first {
            return existing
        }
        if let object = aiEvaluationObject(from: evaluation.overall),
           let comments = object["comments"] as? [[String: Any]],
           let comment = comments.compactMap({ item -> String? in
               guard let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                     aliases.contains(aiNormalizedIdentifier(id)) else {
                   return nil
               }
               return ((item["comment"] as? String) ?? (item["recommendation_comment"] as? String))?
                   .trimmingCharacters(in: .whitespacesAndNewlines)
                   .recommendationNonEmptyText
           }).first {
            return comment
        }
        return aiReview(for: score, evaluation: evaluation)?.recommendationComment.recommendationNonEmptyText
    }

    private func aiReview(for score: RecommendationScore, evaluation: RecommendationAIEvaluation?) -> RecommendationAIReview? {
        guard let evaluation else {
            return nil
        }
        let aliases = aiAliases(for: score)
        if let existing = aliases.compactMap({ evaluation.reviewsByScoreID[$0] }).first {
            return existing
        }
        guard let object = aiEvaluationObject(from: evaluation.overall),
              let reviews = object["reviews"] as? [[String: Any]] else {
            return nil
        }
        return reviews.compactMap { item -> RecommendationAIReview? in
            guard let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  aliases.contains(aiNormalizedIdentifier(id)) else {
                return nil
            }
            return RecommendationAIReview(
                relevance: aiDouble(item["relevance"]),
                novelty: aiDouble(item["novelty"]),
                methodSoundness: aiDouble(item["method_soundness"] ?? item["methodSoundness"]),
                usefulness: aiDouble(item["usefulness"]),
                risk: aiDouble(item["risk"]),
                summary: ((item["summary"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                recommendationComment: ((item["recommendation_comment"] as? String) ?? (item["comment"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                suitableFor: aiStringList(item["suitable_for"]),
                possibleWeaknesses: aiStringList(item["possible_weaknesses"])
            )
        }.first
    }

    private func aiAliases(for score: RecommendationScore) -> Set<String> {
        var aliases: Set<String> = []
        let rawValues = [
            score.id,
            score.candidate.canonicalID,
            score.candidate.externalKey,
            score.candidate.paperID,
            score.candidate.sourceURL
        ].compactMap { $0?.recommendationNonEmptyText }
        for value in rawValues {
            let normalized = aiNormalizedIdentifier(value)
            aliases.insert(normalized)
            if normalized.hasPrefix("external:") {
                aliases.insert(String(normalized.dropFirst("external:".count)))
            }
            if normalized.hasPrefix("paper:") {
                aliases.insert(String(normalized.dropFirst("paper:".count)))
            }
            if normalized.hasPrefix("arxiv:") {
                aliases.insert("external:\(normalized)")
                aliases.insert(String(normalized.dropFirst("arxiv:".count)))
            }
        }
        return aliases
    }

    private func aiNormalizedIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return ""
        }
        if let url = URL(string: trimmed),
           let last = url.pathComponents.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty {
            if url.host?.contains("arxiv.org") == true {
                return "arxiv:\(last.replacingOccurrences(of: ".pdf", with: ""))"
            }
            return last
        }
        return trimmed
    }

    private func aiEvaluationObject(from text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let open = trimmed.firstIndex(of: "{"),
           let close = trimmed.lastIndex(of: "}"),
           open <= close {
            jsonText = String(trimmed[open...close])
        } else {
            jsonText = trimmed
        }
        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func aiDouble(_ value: Any?) -> Double {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }

    private func aiStringList(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let value = value as? String {
            return value
                .components(separatedBy: CharacterSet(charactersIn: ",;；\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private var selectedCategorySummary: String {
        let selected = Self.categoryGroups
            .flatMap(\.options)
            .filter { selectedCategories.contains($0.id) }
            .map(\.id)
        guard !selected.isEmpty else {
            return appModel.localized("未选择领域", "No fields selected")
        }
        let visible = selected.prefix(8).joined(separator: " · ")
        if selected.count > 8 {
            return appModel.localized("\(visible) 等 \(selected.count) 项", "\(visible) and \(selected.count - 8) more")
        }
        return visible
    }

    private var referencePaperSummaryText: String {
        let selected = projectReferencePapers.filter { selectedReferencePaperIDs.contains($0.id) }
        guard !selected.isEmpty else {
            return appModel.localized("选择论文作为推荐参考", "Select papers as recommendation references")
        }
        let visible = selected.prefix(3).map(\.displayTitle).joined(separator: " · ")
        if selected.count > 3 {
            return appModel.localized("\(visible) 等 \(selected.count) 篇", "\(visible) and \(selected.count - 3) more")
        }
        return visible
    }

    private var recommendationHistorySummaryText: String {
        guard let latest = appModel.recommendationHistory.first else {
            return appModel.localized("管理历史推荐", "Manage recommendation history")
        }
        let categories = latest.categories.prefix(3).joined(separator: " · ")
        let categoryText = categories.isEmpty ? appModel.localized("未记录领域", "No fields recorded") : categories
        return appModel.localized(
            "\(latest.scores.count) 篇 · \(categoryText)",
            "\(latest.scores.count) papers · \(categoryText)"
        )
    }

    private var projectReferencePapers: [Paper] {
        appModel.papers(for: project.id)
    }

    private func initializeRecommendationState() {
        if appModel.currentProjectID != project.id {
            appModel.focusResearchProject(project.id)
        }
        selectedCategories = persistedSelectedCategories()
        applyDefaultReferencePapersIfNeeded()
        appModel.loadRecommendationHistory()
        selectTodaysRecommendationHistoryIfNeeded()
    }

    private func selectTodaysRecommendationHistoryIfNeeded() {
        guard !didSelectDefaultHistory,
              appModel.recommendationRunResult == nil,
              let result = appModel.recommendationHistory.first(where: isTodaysRecommendationResult) else {
            return
        }
        didSelectDefaultHistory = true
        appModel.selectRecommendationHistory(result)
    }

    private func isTodaysRecommendationResult(_ result: RecommendationRunResult) -> Bool {
        guard !result.scores.isEmpty else { return false }
        if let contextProjectID = result.contextProjectID, contextProjectID != project.id {
            return false
        }
        let calendar = Calendar.current
        let date = result.sourceDate ?? result.generatedAt
        return calendar.isDateInToday(date)
    }

    private func applyDefaultReferencePapersIfNeeded() {
        guard !didInitializeReferencePapers else {
            return
        }
        let projectPaperIDs = Set(projectReferencePapers.map(\.id))
        guard !projectPaperIDs.isEmpty else {
            return
        }
        selectedReferencePaperIDs = projectPaperIDs
        didInitializeReferencePapers = true
    }

    private func persistSelectedCategories() {
        let categories = parsedCategories
        UserDefaults.standard.set(categories, forKey: recommendationCategoryDefaultsKey)
    }

    private func persistedSelectedCategories() -> Set<String> {
        guard let values = UserDefaults.standard.array(forKey: recommendationCategoryDefaultsKey) as? [String] else {
            return Self.defaultCategoryIDs
        }
        return Set(values).intersection(Self.allCategoryIDs)
    }

    private var recommendationCategoryDefaultsKey: String {
        "sciStation.recommendation.categories.\(workspace.rootURL.path).\(project.id)"
    }

}

private struct RecommendationCategoryGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let options: [RecommendationCategoryOption]
}

private struct RecommendationCategoryOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

private struct RecommendationCategorySelectorSheet: View {
    @EnvironmentObject private var appModel: AppViewModel

    let groups: [RecommendationCategoryGroup]
    @Binding var selectedCategories: Set<String>
    let onDone: () -> Void

    @State private var expandedGroups: Set<String> = ["computer_science", "physics"]
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(appModel.localized("选择 arXiv 领域", "Choose arXiv Fields"), systemImage: "list.bullet.rectangle")
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Text(appModel.localized("已选 \(selectedCategories.count) 项", "\(selectedCategories.count) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(appModel.localized("完成", "Done"), action: onDone)
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                TextField(appModel.localized("搜索领域，例如 高能、hep、机器学习", "Search fields, e.g. high energy, hep, machine learning"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button(appModel.localized("清空选择", "Clear Selection")) {
                    selectedCategories.removeAll()
                }
                .buttonStyle(.bordered)
                .disabled(selectedCategories.isEmpty)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(filteredGroups) { group in
                        categoryGroupSection(group)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 900, maxWidth: 900, minHeight: 460, idealHeight: 640, maxHeight: 640)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredGroups: [RecommendationCategoryGroup] {
        guard !normalizedSearchText.isEmpty else {
            return groups
        }
        return groups.compactMap { group in
            let filteredOptions = group.options.filter { option in
                option.id.lowercased().contains(normalizedSearchText)
                || option.title.lowercased().contains(normalizedSearchText)
                || option.detail.lowercased().contains(normalizedSearchText)
            }
            guard !filteredOptions.isEmpty else {
                return nil
            }
            return RecommendationCategoryGroup(
                id: group.id,
                title: group.title,
                systemImage: group.systemImage,
                options: filteredOptions
            )
        }
    }

    private func categoryGroupSection(_ group: RecommendationCategoryGroup) -> some View {
        DisclosureGroup(isExpanded: categoryGroupBinding(group.id)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(group.options) { option in
                    categoryOptionButton(option)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.systemImage)
                    .foregroundStyle(.secondary)
                Text(group.title)
                    .font(.headline)
                Text(appModel.localized("\(selectedCount(in: group)) / \(group.options.count) 已选", "\(selectedCount(in: group)) / \(group.options.count) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(appModel.localized("全选", "Select All")) {
                    selectAll(in: group)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Button(appModel.localized("清空", "Clear")) {
                    clear(in: group)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(selectedCount(in: group) == 0)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func categoryOptionButton(_ option: RecommendationCategoryOption) -> some View {
        Button {
            toggleCategory(option.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selectedCategories.contains(option.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedCategories.contains(option.id) ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.detail)
                        .font(.caption.weight(.semibold))
                    Text("\(option.id) · \(option.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selectedCategories.contains(option.id) ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(Text("\(option.id) · \(option.title)"))
    }

    private func categoryGroupBinding(_ id: String) -> Binding<Bool> {
        Binding {
            expandedGroups.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedGroups.insert(id)
            } else {
                expandedGroups.remove(id)
            }
        }
    }

    private func toggleCategory(_ id: String) {
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }
    }

    private func selectedCount(in group: RecommendationCategoryGroup) -> Int {
        group.options.filter { selectedCategories.contains($0.id) }.count
    }

    private func selectAll(in group: RecommendationCategoryGroup) {
        for option in group.options {
            selectedCategories.insert(option.id)
        }
    }

    private func clear(in group: RecommendationCategoryGroup) {
        for option in group.options {
            selectedCategories.remove(option.id)
        }
    }
}

private struct RecommendationReferencePaperSheet: View {
    @EnvironmentObject private var appModel: AppViewModel

    let project: ResearchProject
    @Binding var selectedPaperIDs: Set<Paper.ID>
    let onDone: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(appModel.localized("选择相关论文", "Select Related Papers"), systemImage: "books.vertical")
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Text(appModel.localized("已选 \(selectedPaperIDs.count) 篇", "\(selectedPaperIDs.count) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(appModel.localized("完成", "Done"), action: onDone)
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                TextField(appModel.localized("搜索标题、作者、标签", "Search title, author, tag"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button(appModel.localized("全选项目论文", "Select Project")) {
                    selectedPaperIDs = Set(projectPapers.map(\.id))
                }
                .buttonStyle(.bordered)
                .disabled(projectPapers.isEmpty || selectedPaperIDs == Set(projectPapers.map(\.id)))

                Button(appModel.localized("选择筛选结果", "Select Filtered")) {
                    selectedPaperIDs.formUnion(filteredPapers.map(\.id))
                }
                .buttonStyle(.bordered)
                .disabled(filteredPapers.isEmpty)

                Button(appModel.localized("清空", "Clear")) {
                    selectedPaperIDs.removeAll()
                }
                .buttonStyle(.bordered)
                .disabled(selectedPaperIDs.isEmpty)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredPapers) { paper in
                        paperRow(paper)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 820, maxWidth: 820, minHeight: 460, idealHeight: 620, maxHeight: 620)
    }

    private var filteredPapers: [Paper] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return projectPapers.filter { paper in
            guard !normalizedSearch.isEmpty else {
                return true
            }
            let haystack = [
                paper.displayTitle,
                paper.authorsDisplay,
                paper.tags.joined(separator: " "),
                paper.categories.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(normalizedSearch)
        }
    }

    private var projectPapers: [Paper] {
        appModel.papers(for: project.id)
    }

    private func paperRow(_ paper: Paper) -> some View {
        Button {
            toggle(paper.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedPaperIDs.contains(paper.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedPaperIDs.contains(paper.id) ? Color.accentColor : .secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(paper.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let year = paper.year {
                            Label(String(year), systemImage: "calendar")
                        }
                        Text(paper.authorsDisplay)
                            .lineLimit(1)
                        if !paper.projectIDs.isEmpty {
                            Text(paper.projectIDs.map(appModel.projectName(for:)).joined(separator: " · "))
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(selectedPaperIDs.contains(paper.id) ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: Paper.ID) {
        if selectedPaperIDs.contains(id) {
            selectedPaperIDs.remove(id)
        } else {
            selectedPaperIDs.insert(id)
        }
    }
}

private struct RecommendationHistoryManagerSheet: View {
    @EnvironmentObject private var appModel: AppViewModel

    let onSelect: (RecommendationRunResult) -> Void
    let onDone: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(appModel.localized("管理历史推荐", "Manage Recommendation History"), systemImage: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Text(appModel.localized("\(filteredHistory.count) 条记录", "\(filteredHistory.count) runs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    appModel.loadRecommendationHistory()
                } label: {
                    Label(appModel.localized("刷新", "Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Button(appModel.localized("完成", "Done"), action: onDone)
                    .buttonStyle(.borderedProminent)
            }

            TextField(appModel.localized("搜索关键词、领域或来源", "Search query, field, or source"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(appModel.localized("暂无历史推荐", "No recommendation history yet"), systemImage: "tray")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(appModel.localized("点击推荐后，结果会出现在这里，之后可从历史记录恢复或归档。", "After fetching recommendations, results will appear here and can be restored or archived."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredHistory) { result in
                            historyRow(result)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 820, maxWidth: 920, minHeight: 420, idealHeight: 600, maxHeight: 680)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredHistory: [RecommendationRunResult] {
        guard !normalizedSearchText.isEmpty else {
            return appModel.recommendationHistory
        }
        return appModel.recommendationHistory.filter { result in
            let haystack = [
                result.query,
                result.categories.joined(separator: " "),
                result.sourceNote ?? "",
                result.generatedAt.formatted(date: .abbreviated, time: .shortened)
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(normalizedSearchText)
        }
    }

    private func historyRow(_ result: RecommendationRunResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onSelect(result)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(result.generatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout.weight(.semibold))
                        if appModel.recommendationRunResult?.id == result.id {
                            Label(appModel.localized("当前", "Current"), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(result.query.isEmpty ? appModel.localized("无关键词", "No query") : result.query)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(result.categories.prefix(8).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Label(appModel.localized("\(result.scores.count) 篇推荐", "\(result.scores.count) recommendations"), systemImage: "sparkles")
                        Label(appModel.localized("参考 \(result.referencePaperIDs.count) 篇", "\(result.referencePaperIDs.count) refs"), systemImage: "books.vertical")
                        if let sourceNote = result.sourceNote {
                            Text(sourceNote)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                appModel.archiveRecommendationHistory(result)
            } label: {
                Label(appModel.localized("归档", "Archive"), systemImage: "archivebox")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(appModel.localized("归档这条历史推荐", "Archive this recommendation"))
        }
        .padding(12)
        .background(appModel.recommendationRunResult?.id == result.id ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RecommendationScoreRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let score: RecommendationScore
    let displayRank: Int
    let scope: RecommendationTarget
    let aiComment: String?
    let aiReview: RecommendationAIReview?
    let feedback: RecommendationFeedbackType?
    let onAddToLibrary: () -> Void
    let onAddReadingTodo: () -> Void
    let onFeedback: (RecommendationFeedbackType) -> Void
    let onOpenReading: () -> Void
    let isInLibrary: Bool
    let isInReadingTodo: Bool
    let isAddingToLibrary: Bool
    let isAddingReadingTodo: Bool
    @State private var isShowingScoreDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text("#\(displayRank)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(Int((score.total * 100).rounded()))")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("/100")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Button(action: openSource) {
                        Text(score.candidate.displayTitle)
                            .font(.headline)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if !score.candidate.authors.isEmpty {
                        Text(score.candidate.authors.prefix(6).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let dateText = publicationDateText {
                            Label(dateText, systemImage: "calendar")
                        }
                        if !score.candidate.categories.isEmpty {
                            Text(score.candidate.categories.prefix(4).joined(separator: " · "))
                        }
                        if let externalKey = score.candidate.externalKey {
                            Text(externalKey)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Text(score.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    mainScoreChips

                    if let aiReview {
                        aiReviewSection(aiReview)
                    } else if let aiComment, !aiComment.isEmpty {
                        Label(aiComment, systemImage: "sparkles")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    if isInReadingTodo {
                        Label(appModel.localized("已在阅读 Todo", "In Reading Todo"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        Button(action: onOpenReading) {
                            Label(appModel.localized("查看任务", "View task"), systemImage: "checklist")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if isInLibrary {
                        Label(appModel.localized("已在论文库", "In Library"), systemImage: "books.vertical.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        Button(action: onAddReadingTodo) {
                            if isAddingReadingTodo {
                                Label {
                                    Text(appModel.localized("加入中", "Adding"))
                                } icon: {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            } else {
                                Label(appModel.localized("加入阅读 Todo", "Add Reading Todo"), systemImage: "book.badge.plus")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isAddingReadingTodo)
                    } else {
                        Button(action: onAddToLibrary) {
                            if isAddingToLibrary {
                                Label {
                                    Text(appModel.localized("加入中", "Adding"))
                                } icon: {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            } else {
                                Label(appModel.localized("加入论文库", "Add to Library"), systemImage: "tray.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isAddingToLibrary)
                    }
                    feedbackButtons
                }
            }

            DisclosureGroup(isExpanded: $isShowingScoreDetails) {
                LazyVGrid(columns: Self.detailScoreColumns, alignment: .leading, spacing: 8) {
                    ForEach(detailScoreItems, id: \.title) { item in
                        scoreBlock(item.title, value: item.value)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(appModel.localized("详细评分", "Score details"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 66)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var publicationDateText: String? {
        if let publishedAt = score.candidate.publishedAt {
            return Self.paperDateFormatter.string(from: publishedAt)
        }
        if let year = score.candidate.publishedYear {
            return String(year)
        }
        return nil
    }

    private var mainScoreChips: some View {
        HStack(spacing: 6) {
            scoreChip(appModel.localized("关键词", "Keyword"), value: score.features.keywordRelevance)
            scoreChip(appModel.localized("参考", "Seed"), value: score.features.seedSimilarity)
            scoreChip(appModel.localized("新鲜", "Recent"), value: score.features.recency)
            scoreChip(appModel.localized("新颖", "Novel"), value: score.features.novelty)
            if score.features.aiScore > 0 {
                scoreChip("AI", value: score.features.aiScore)
            }
        }
    }

    private func scoreChip(_ title: String, value: Double) -> some View {
        VStack(spacing: 1) {
            Text("\(Int((value * 100).rounded()))")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var detailScoreItems: [(title: String, value: Double)] {
        [
            (appModel.localized("关键词相关", "Keyword"), score.features.keywordRelevance),
            (appModel.localized("参考相似", "Seed"), score.features.seedSimilarity),
            (appModel.localized("项目上下文", "Project"), score.features.projectContextSimilarity),
            (appModel.localized("arXiv 新鲜度", "Recency"), score.features.recency),
            (appModel.localized("新颖度", "Novelty"), score.features.novelty),
            (appModel.localized("质量信号", "Quality"), score.features.quality),
            (appModel.localized("AI 评分", "AI"), score.features.aiScore),
            (appModel.localized("反馈偏好", "Feedback"), score.features.feedback),
            (appModel.localized("相关论文", "Related"), score.features.libraryInterestSimilarity),
            (appModel.localized("作者重叠", "Authors"), score.features.authorOverlapWithCore),
            (appModel.localized("重复惩罚", "Duplicate"), score.features.duplicatePenalty)
        ]
    }

    private func scoreBlock(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int((value * 100).rounded()))")
                .font(.headline.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var feedbackButtons: some View {
        HStack(spacing: 6) {
            Button {
                onFeedback(.like)
            } label: {
                Image(systemName: feedback == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .help(appModel.localized("喜欢：强化类似推荐", "Like: prefer similar papers"))

            Button {
                onFeedback(.dislike)
            } label: {
                Image(systemName: feedback == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .help(appModel.localized("不感兴趣：降低类似推荐", "Dislike: reduce similar papers"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func aiReviewSection(_ review: RecommendationAIReview) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(appModel.localized("AI 逐篇评价", "AI paper review"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Text(appModel.localized("风险 \(Int((review.risk * 100).rounded()))%", "Risk \(Int((review.risk * 100).rounded()))%"))
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(review.risk > 0.65 ? Color.orange.opacity(0.18) : Color.green.opacity(0.16), in: Capsule())
            }
            if !review.recommendationComment.isEmpty {
                Text(review.recommendationComment)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !review.summary.isEmpty {
                Text(review.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                featurePill(appModel.localized("相关", "Rel"), value: review.relevance)
                featurePill(appModel.localized("新颖", "Nov"), value: review.novelty)
                featurePill(appModel.localized("方法", "Method"), value: review.methodSoundness)
                featurePill(appModel.localized("有用", "Use"), value: review.usefulness)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func featurePill(_ title: String, value: Double) -> some View {
        Text("\(title) \(Int((value * 100).rounded()))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func featureRow(_ title: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 160, alignment: .leading)
            ProgressView(value: value)
                .frame(maxWidth: 260)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func openSource() {
        guard let urlString = score.candidate.sourceURL ?? score.candidate.externalKey?.recommendationArxivURLString,
              let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static let paperDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let detailScoreColumns = [
        GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 8, alignment: .leading)
    ]
}

private extension String {
    var recommendationNonEmptyText: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var recommendationArxivURLString: String? {
        let lowered = lowercased()
        guard lowered.hasPrefix("arxiv:") else {
            return nil
        }
        let id = String(dropFirst("arxiv:".count))
        return "https://arxiv.org/abs/\(id)"
    }
}

#if DEBUG
#Preview("Recommendations") {
    RecommendationView(workspace: PreviewFixtures.workspace, project: PreviewFixtures.project)
        .environmentObject(AppViewModel())
        .frame(width: 1000, height: 720)
}
#endif
