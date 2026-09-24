import SwiftUI

struct AnalysisResultView: View {
    let report: SpeechReport
    var isLoading: Bool = false
    var onOpenTranscript: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            MeshBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ResultsScoreHeader(score: report.overallScore, feedback: report.feedback)
                        .padding(.top, 6)

                    ResultsMetricsGrid(report: report)

                    ResultsAISummary(report: report, isLoading: isLoading)

                    if !isLoading, let action = onOpenTranscript {
                        Button(action: action) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("View Transcript")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }

                    if !isLoading, !report.insights.isEmpty {
                        ResultsInsightsList(userInsights: report.insights)
                    }
                }
                .padding()
                .padding(.bottom, 40)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isLoading)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
