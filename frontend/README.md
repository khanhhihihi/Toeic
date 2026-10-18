# Readia · Quản trị TOEIC

Giao diện Flutter Web quản trị ngân hàng đề thi TOEIC, kết nối API ASP.NET Core trong thư mục `backend`.

## Chạy ứng dụng

Mở hai terminal từ thư mục gốc của dự án.

Terminal 1 — backend:

```powershell
dotnet run --project .\backend\backend.csproj --launch-profile http
```

Backend chạy tại `http://localhost:5134`; kiểm tra trạng thái bằng `http://localhost:5134/health`.

Terminal 2 — frontend:

```powershell
Set-Location .\frontend
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8765
```

Mặc định Flutter gọi `http://localhost:5134`. Có thể đổi địa chỉ backend khi build:

```powershell
flutter build web --dart-define=API_BASE_URL=https://your-api.example
```

CORS của backend cho phép `http://127.0.0.1:8765` và `http://localhost:8765`. Ở môi trường Development, các origin HTTP trên `localhost` hoặc loopback IP cũng được cho phép ở mọi cổng để tương thích với cổng ngẫu nhiên do `flutter run -d chrome` chọn. Cập nhật allowlist trong `backend/Program.cs` khi triển khai frontend từ origin production.

## Chức năng đã kết nối

- Tải danh sách đề và thống kê từ backend; tìm kiếm, lọc, sắp xếp và phân trang ở frontend.
- Tải lên `.docx` tối đa 20 MB để tạo đề nháp hoặc thay tài liệu của một đề nháp.
- Kiểm tra lại tệp, xem các lỗi do backend phân tích, và tải tệp Word đã sửa lên để phân tích lại.
- Xem trước câu hỏi, lựa chọn, đáp án, lời giải và đoạn đọc mà backend đọc được.
- Xuất bản đề hợp lệ hoặc xóa đề nháp; dữ liệu và tệp nguồn được lưu tại `backend/App_Data/`.

## Định dạng Word được phân tích

Backend đọc các đoạn văn bản trong `word/document.xml`. Có thể dùng bộ tag `[PASSAGE]`/`[PASSAGES]`, `[QUESTION]`, `[OPTION]`, `[ANSWER]`, `[EXPLANATION]`; đồng thời hỗ trợ định dạng `Reading_v07_tagged.docx` với `[Q:n]`, `[TEXT]`, `[A]`–`[D]`, `[KEY]`, `[HINT]` và các đoạn `[PASSAGE]`...`[/PASSAGE]`. Đề phải có đúng 100 câu, đủ lựa chọn A–D, đáp án đúng hợp lệ và lời giải cho mỗi câu. Tệp Word chưa gắn tag câu hỏi (như `Reading_v07_text.docx`) cần được gắn tag trước khi nhập. Giao diện không giả lập việc sửa lỗi trực tiếp trong tài liệu.

Hiện parser tập trung vào văn bản trong DOCX; ảnh nhúng và bố cục bảng phức tạp chưa được trích xuất/hiển thị. Lưu trữ JSON/file trên máy chủ phù hợp chạy local hoặc thử nghiệm; chưa có database, xác thực hay phân quyền. Cần bổ sung các thành phần này trước khi triển khai production.

## Kiểm tra

```powershell
flutter analyze
flutter test
flutter build web
dotnet build .\backend\backend.csproj
```
