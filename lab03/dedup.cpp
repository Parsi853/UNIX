#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace fs = std::filesystem;
using Buffer = std::array<char, 64 * 1024>;

std::ifstream open_file(const fs::path& path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("Не удалось открыть файл: " + path.string());
    return input;
}

std::streamsize read_chunk(std::ifstream& input, Buffer& buffer)
{
    input.read(buffer.data(), buffer.size());
    if (input.bad() || (input.fail() && !input.eof())) {
        throw std::runtime_error("Ошибка чтения файла");
    }
    return input.gcount();
}

std::uint64_t hash_file(const fs::path& path)
{
    auto input = open_file(path);
    Buffer buffer;
    // Начальное значение и множитель из алгоритма FNV-1a для 64 бит.
    std::uint64_t hash = 14695981039346656037ULL;
    while (const auto size = read_chunk(input, buffer)) {
        for (std::streamsize i = 0; i < size; ++i) {
            hash ^= static_cast<unsigned char>(buffer[i]);
            hash *= 1099511628211ULL;
        }
    }
    return hash;
}

bool same_contents(const fs::path& first, const fs::path& second)
{
    auto a = open_file(first);
    auto b = open_file(second);
    Buffer x, y;
    for (;;) {
        const auto n = read_chunk(a, x);
        if (n != read_chunk(b, y) || !std::equal(x.begin(), x.begin() + n, y.begin())) {
            return false;
        }
        if (n == 0) return true;
    }
}

void replace_with_link(const fs::path& original, const fs::path& duplicate)
{
    const auto parent = duplicate.parent_path();
    for (std::uint64_t number = 0;; ++number) {
        const auto temp = parent / (".unix-dedup-" + std::to_string(number));
        const auto link = temp / "link";
        std::error_code error;
        if (!fs::create_directory(temp, error)) {
            if (!error || error == std::errc::file_exists) continue;
            throw fs::filesystem_error("Создание временного каталога", temp, error);
        }

        // Сначала создаём ссылку рядом с дубликатом. Если link не удался,
        // дубликат останется на месте. rename заменяет его одним действием.
        fs::create_hard_link(original, link, error);
        if (!error) fs::rename(link, duplicate, error);

        std::error_code cleanup_error;
        fs::remove(link, cleanup_error);
        fs::remove(temp, cleanup_error);
        if (error) throw fs::filesystem_error("Замена файла жёсткой ссылкой", original, duplicate, error);
        return;
    }
}

int main(int argc, char* argv[])
{
    const bool dry_run = argc == 3 && std::string(argv[1]) == "--dry-run";
    if (!(dry_run || argc == 2)) {
        std::cerr << "Запуск: dedup [--dry-run] КАТАЛОГ\n";
        return 2;
    }

    try {
        const auto root = fs::absolute(argv[dry_run ? 2 : 1]);
        if (!fs::is_directory(fs::symlink_status(root))) {
            std::cerr << "Нужно указать обычный каталог: " << root << '\n';
            return 2;
        }

        std::vector<fs::path> files;
        for (const auto& entry : fs::recursive_directory_iterator(root)) {
            if (fs::is_regular_file(entry.symlink_status())) files.push_back(entry.path());
        }
        std::sort(files.begin(), files.end());

        std::size_t replaced = 0, linked = 0, errors = 0;
        std::unordered_map<std::uint64_t, std::vector<fs::path>> groups;
        for (const auto& file : files) {
            try {
                auto& representatives = groups[hash_file(file)];
                bool found = false;
                for (const auto& first : representatives) {
                    if (fs::equivalent(first, file)) {
                        ++linked;
                        found = true;
                        break;
                    }
                    // Совпадение хэшей ещё не означает, что файлы одинаковые.
                    if (!same_contents(first, file)) continue;
                    if (!dry_run) replace_with_link(first, file);
                    std::cout << (dry_run ? "Будет создана ссылка " : "Создана ссылка ")
                              << file << " -> " << first << '\n';
                    ++replaced;
                    found = true;
                    break;
                }
                if (!found) representatives.push_back(file);
            } catch (const std::exception& error) {
                std::cerr << file << ": " << error.what() << '\n';
                ++errors;
            }
        }
        std::cout << "Файлов=" << files.size()
                  << (dry_run ? " к_замене=" : " заменено=") << replaced
                  << " уже_связаны=" << linked << " ошибок=" << errors << '\n';
        return errors ? 1 : 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
