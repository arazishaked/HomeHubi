import SwiftUI

// MARK: - רשימות מעוצבות ב-SwiftUI טהור
//
// List ו-Form של SwiftUI מצוירים על ידי UIKit, ובחלק ממכשירי ה-iOS בעברית הטקסט בתוכם הופיע במראה (הפוך).
// הרכיבים כאן נראים כמו רשימה מקובצת של iOS אבל בנויים מ-ScrollView ו-VStack בלבד, כך שהכיווניות תמיד נכונה.

struct GList<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

/// מסדר את השורות של קטע: ריווח, גובה מינימלי ומפריד דק בין שורות
private struct GRowsLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let lastID = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                if child.id != lastID {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}

struct GSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            _VariadicView.Tree(GRowsLayout()) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension GSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension GSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension GSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension GSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

/// שורת ניווט עם חץ, כמו בהגדרות של iOS
struct GLink<Label: View>: View {
    let value: Route
    private let label: Label

    init(value: Route, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 8) {
                label.foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// בחירה מתוך רשימה: הכותרת בצד אחד והערך הנבחר בצד השני
struct GPicker<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    private let options: Options

    init(_ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Options) {
        self.title = title
        self._selection = selection
        self.options = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) { options }
                .pickerStyle(.menu)
                .labelsHidden()
        }
    }
}

/// שורת מידע: כותרת וערך
struct GLabeled: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
