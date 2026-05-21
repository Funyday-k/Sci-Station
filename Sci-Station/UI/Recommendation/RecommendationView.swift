import AppKit
import SwiftUI

struct RecommendationView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    @State private var query: String
    @State private var selectedCategories: Set<String>
    @State private var topK: Int = 10
    @State private var selectedAIModel: String = "deepseek-v4-flash"
    @State private var selectedScopeIdentifier: String
    @State private var isCategorySelectorPresented = false

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

    init(workspace: ResearchWorkspace, project: ResearchProject) {
        self.workspace = workspace
        self.project = project
        _query = State(initialValue: project.name)
        _selectedCategories = State(initialValue: Set(["cs.AI", "cs.CL", "cs.CV", "cs.LG"]))
        _selectedScopeIdentifier = State(initialValue: QueueScope.project(project.id).identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            controls
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
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
        .onAppear {
            if appModel.currentProjectID != project.id {
                appModel.focusResearchProject(project.id)
            }
            appModel.loadRecommendationHistory()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(appModel.localized("论文推荐", "Paper Recommendations"), systemImage: ProjectSpaceTabIcon.systemImage(for: "recommendations"))
                    .font(.largeTitle.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    appModel.selectProjectSpaceTab("reading")
                } label: {
                    Label(appModel.localized("打开 Reading", "Open Reading"), systemImage: ProjectSpaceTabIcon.systemImage(for: "reading"))
                }
                .buttonStyle(.bordered)
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
                "推荐只从 arXiv 获取候选，不再从本地文库、图谱或旧队列生成候选。你可以把结果直接加入统一的 Reading。",
                "Recommendations fetch candidates only from arXiv, not from the local library, graph, or old queue. Add results directly to unified Reading."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField(appModel.localized("关键词，例如 diffusion planning", "Keywords, e.g. diffusion planning"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 280)

                Stepper(value: $topK, in: 1...100) {
                    Text(appModel.localized("推荐 \(topK) 篇", "Recommend \(topK) papers"))
                        .font(.callout.monospacedDigit())
                }
                .frame(width: 170)

                Picker(appModel.localized("AI 模型", "AI model"), selection: $selectedAIModel) {
                    ForEach(aiModelOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
            }

            HStack(spacing: 12) {
                Picker(appModel.localized("加入范围", "Add scope"), selection: $selectedScopeIdentifier) {
                    ForEach(availableScopes, id: \.identifier) { scope in
                        Text(scopeLabel(for: scope)).tag(scope.identifier)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

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

                Spacer(minLength: 0)
            }

            categorySelectionSummary
        }
        .padding(.bottom, 8)
    }

    private var categorySelectionSummary: some View {
        HStack(spacing: 10) {
            Label(appModel.localized("领域 \(selectedCategories.count) 项", "\(selectedCategories.count) fields"), systemImage: "tag")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(selectedCategorySummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                isCategorySelectorPresented = true
            } label: {
                Label(appModel.localized("选择领域", "Choose Fields"), systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            HStack(alignment: .top, spacing: 16) {
                resultsPane
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                historyPane
                    .frame(width: 240, alignment: .top)
                    .frame(maxHeight: 360, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var resultsPane: some View {
        if let result = appModel.recommendationRunResult, !result.scores.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    resultSummary(result)
                    ForEach(result.scores) { score in
                        RecommendationScoreRow(
                            score: score,
                            scope: selectedScope,
                            aiComment: result.aiEvaluation?.commentsByScoreID[score.id],
                            onAdd: {
                                appModel.addRecommendationToReadingList(score, scope: selectedScope)
                            },
                            isAdded: appModel.isRecommendationInReadingList(score, scope: selectedScope)
                        )
                    }
                }
                .padding(.vertical, 14)
            }
        } else {
            emptyRecommendationState
        }
    }

    private var emptyRecommendationState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appModel.localized("还没有 arXiv 推荐", "No arXiv recommendations yet"), systemImage: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(appModel.localized("选择推荐方向和数量后点击推荐。默认优先读取当天论文；当天没有匹配结果时，会延顺昨日未推荐论文。", "Choose directions and a count, then recommend. Today's papers are used first; if none match, unrecommended papers from yesterday are used."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: refresh) {
                Label(appModel.localized("获取推荐", "Fetch Recommendations"), systemImage: "arrow.down.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.isRefreshingRecommendations)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(.top, 24)
    }

    private func resultSummary(_ result: RecommendationRunResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(result.sourceNote ?? appModel.localized("arXiv 推荐", "arXiv recommendations"), systemImage: "calendar.badge.clock")
                if let sourceDate = result.sourceDate {
                    Text(sourceDate.formatted(date: .abbreviated, time: .omitted))
                }
                Spacer(minLength: 0)
                Text(appModel.localized("共 \(result.scores.count) 篇", "\(result.scores.count) papers"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if appModel.isEvaluatingRecommendationsWithAI {
                Label(appModel.localized("AI 正在阅读标题和摘要并生成评价…", "AI is reading titles and abstracts for evaluation…"), systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let evaluation = result.aiEvaluation {
                VStack(alignment: .leading, spacing: 6) {
                    Label(appModel.localized("AI 总评", "AI evaluation"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                    Text(evaluation.overall)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(evaluation.model)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let status = appModel.recommendationAIEvaluationStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appModel.localized("历史推荐", "History"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    appModel.loadRecommendationHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            if appModel.recommendationHistory.isEmpty {
                Text(appModel.localized("暂无历史记录", "No history yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appModel.recommendationHistory) { result in
                            Button {
                                appModel.selectRecommendationHistory(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.generatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption.weight(.semibold))
                                    Text(result.categories.prefix(4).joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(appModel.localized("\(result.scores.count) 篇推荐", "\(result.scores.count) recommendations"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(appModel.recommendationRunResult?.id == result.id ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var availableScopes: [QueueScope] {
        appModel.availableResearchQueueScopes
    }

    private var selectedScope: QueueScope {
        QueueScope(identifier: selectedScopeIdentifier) ?? .project(project.id)
    }

    private func refresh() {
        appModel.refreshArxivRecommendations(project: project, query: query, categories: parsedCategories, topK: topK, aiModel: selectedAIModel)
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

    private func scopeLabel(for scope: QueueScope) -> String {
        switch scope {
        case .workspace:
            return appModel.localized("工作区", "Workspace")
        case .project:
            return project.name
        }
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
        .frame(width: 900, height: 640)
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

private struct RecommendationScoreRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let score: RecommendationScore
    let scope: QueueScope
    let aiComment: String?
    let onAdd: () -> Void
    let isAdded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text("#\(score.rank)")
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
                        if let year = score.candidate.publishedYear {
                            Label(String(year), systemImage: "calendar")
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

                    if let aiComment, !aiComment.isEmpty {
                        Label(aiComment, systemImage: "sparkles")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    if isAdded {
                        Label(appModel.localized("已在 Reading", "In Reading"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Button(action: onAdd) {
                            Label(appModel.localized("加入 Reading", "Add to Reading"), systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            VStack(spacing: 8) {
                featureRow(appModel.localized("arXiv 新鲜度", "arXiv recency"), value: score.features.recency)
                featureRow(appModel.localized("关键词覆盖", "Keyword coverage"), value: score.features.openGapCoverage)
                featureRow(appModel.localized("Reading 去重惩罚", "Reading duplicate penalty"), value: score.features.queuePressurePenalty)
            }
            .padding(.leading, 66)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
}

private extension String {
    var recommendationArxivURLString: String? {
        let lowered = lowercased()
        guard lowered.hasPrefix("arxiv:") else {
            return nil
        }
        let id = String(dropFirst("arxiv:".count))
        return "https://arxiv.org/abs/\(id)"
    }
}
