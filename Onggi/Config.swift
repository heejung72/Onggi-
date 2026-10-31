import Foundation

/// Supabase 프로젝트 정보.
/// Supabase 대시보드 > Project Settings > API 에서 복사해 붙여넣으세요.
/// anon(public) 키는 앱에 넣어도 되는 공개 키입니다. service_role 키는 절대 넣지 마세요.
enum Config {
    static let supabaseURL = "https://hzfwkijbvcerpzvtvbxs.supabase.co"
    static let supabaseAnonKey = "sb_publishable_VvHegKpcoeJZrF_KpeB0kQ_EfYAPl1F"

    /// 바탕화면에 동시에 보이는 최대 캐릭터 수 (그룹 최대 인원과 같음)
    static let maxMembers = 10
    /// 실시간 연결이 끊겼을 때를 대비한 주기적 새로고침 간격(초)
    static let pollInterval: TimeInterval = 20
}
