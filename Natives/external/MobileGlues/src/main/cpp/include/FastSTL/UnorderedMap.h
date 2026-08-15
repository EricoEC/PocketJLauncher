#pragma once

#include <utility>
#include <memory>
#include <functional>
#include <stdexcept>
#include <iterator>
#include <cstring>
#include <cstdint>
#include <algorithm>
#include <type_traits>

namespace FastSTL {
    template <class Key, class T, class Hash = std::hash<Key>, class KeyEqual = std::equal_to<Key>,
              class Allocator = std::allocator<std::pair<const Key, T>>>
    class unordered_map;

    namespace detail {
        template <typename MapType, bool IsConst>
        class map_iterator {
        public:
            using iterator_category = std::forward_iterator_tag;
            using map_type = MapType;
            using value_type = typename map_type::value_type;
            using difference_type = typename map_type::difference_type;

            using pointer = std::conditional_t<IsConst, typename map_type::const_pointer, typename map_type::pointer>;
            using reference =
                std::conditional_t<IsConst, typename map_type::const_reference, typename map_type::reference>;
            using map_pointer = std::conditional_t<IsConst, const map_type*, map_type*>;

        private:
            map_pointer m_map = nullptr;
            typename map_type::size_type m_index = 0;

            void advance() {
                if (m_map) {
                    while (m_index < m_map->bucket_count() && !m_map->is_occupied(m_index)) {
                        ++m_index;
                    }
                }
            }

        public:
            map_iterator() = default;
            map_iterator(map_pointer map, typename map_type::size_type index) : m_map(map), m_index(index) {
                if (m_map && m_index < m_map->bucket_count()) {
                    advance();
                }
            }

            map_iterator(const map_iterator<MapType, false>& other) : m_map(other.m_map), m_index(other.m_index) {}

            reference operator*() const { return m_map->m_buckets[m_index]; }
            pointer operator->() const { return m_map->m_buckets + m_index; }

            map_iterator& operator++() {
                if (m_map) {
                    ++m_index;
                    advance();
                }
                return *this;
            }

            map_iterator operator++(int) {
                map_iterator tmp = *this;
                ++(*this);
                return tmp;
            }

            friend bool operator==(const map_iterator& lhs, const map_iterator& rhs) {
                return lhs.m_map == rhs.m_map && lhs.m_index == rhs.m_index;
            }

            friend bool operator!=(const map_iterator& lhs, const map_iterator& rhs) { return !(lhs == rhs); }

            friend map_type;
            template <typename, bool>
            friend class map_iterator;
        };

    } // namespace detail

    template <class Key, class T, class Hash, class KeyEqual, class Allocator>
    class unordered_map {
        template <typename, bool>
        friend class detail::map_iterator;

    public:
        using key_type = Key;
        using mapped_type = T;
        using value_type = std::pair<const Key, T>;
        using size_type = std::size_t;
        using difference_type = std::ptrdiff_t;
        using hasher = Hash;
        using key_equal = KeyEqual;
        using allocator_type = Allocator;
        using reference = value_type&;
        using const_reference = const value_type&;
        using pointer = typename std::allocator_traits<Allocator>::pointer;
        using const_pointer = typename std::allocator_traits<Allocator>::const_pointer;
        using iterator = detail::map_iterator<unordered_map, false>;
        using const_iterator = detail::map_iterator<unordered_map, true>;

    private:
        enum class State : uint8_t {
            Occupied = 0b00,
            Deleted = 0b01,
            Empty = 0b10
        };
        static constexpr size_type FLAGS_PER_U32 = 16;

        pointer m_buckets = nullptr;
        uint32_t* m_flags = nullptr;

        size_type m_bucket_count = 0;
        size_type m_size = 0;
        size_type m_occupied = 0;
        float m_max_load_factor = 0.5f;

        hasher m_hasher;
        key_equal m_key_equal;
        allocator_type m_allocator;

        using FlagAlloc = typename std::allocator_traits<allocator_type>::template rebind_alloc<uint32_t>;

        State get_state(size_type i) const {
            const uint32_t flag_word = m_flags[i >> 4];
            const size_type shift = (i & (FLAGS_PER_U32 - 1)) * 2;
            return static_cast<State>((flag_word >> shift) & 0b11);
        }

        void set_state(size_type i, State state) {
            uint32_t& flag_word = m_flags[i >> 4];
            const size_type shift = (i & (FLAGS_PER_U32 - 1)) * 2;
            flag_word &= ~(0b11UL << shift);
            flag_word |= (static_cast<uint32_t>(state) << shift);
        }

        bool is_occupied(size_type i) const { return get_state(i) == State::Occupied; }

        static size_type roundup32(size_type n) {
            if (n < 4) n = 4;
            --n;
            n |= n >> 1;
            n |= n >> 2;
            n |= n >> 4;
            n |= n >> 8;
            n |= n >> 16;
            if constexpr (sizeof(size_type) > 4) n |= n >> 32;
            return ++n;
        }

        template <typename K>
        size_type find_key(const K& key) const {
            if (m_bucket_count == 0) return m_bucket_count;

            const size_type mask = m_bucket_count - 1;
            const size_type k = static_cast<size_type>(m_hasher(key));
            size_type i = k & mask;
            const size_type start = i;

            const uint32_t* flags = m_flags;
            const pointer buckets = m_buckets;
            constexpr size_type flags_mask = FLAGS_PER_U32 - 1;

            size_type word_idx = i >> 4;
            uint32_t flag_word = flags[word_idx];

            while (true) {
                const size_type shift = (i & flags_mask) * 2;
                State current_state = static_cast<State>((flag_word >> shift) & 0b11);
                if (current_state == State::Occupied) {
                    if (m_key_equal(buckets[i].first, key)) {
                        return i;
                    }
                } else if (current_state == State::Empty) {
                    return m_bucket_count;
                }

                i = (i + 1) & mask;
                if (i == start) break;

                const size_type new_word_idx = i >> 4;
                if (new_word_idx != word_idx) {
                    word_idx = new_word_idx;
                    flag_word = flags[word_idx];
                }
            }
            return m_bucket_count;
        }

        template <typename K>
        size_type find_insert_slot(const K& key) const {
            const size_type mask = m_bucket_count - 1;
            const size_type k = static_cast<size_type>(m_hasher(key));
            size_type i = k & mask;
            const size_type start = i;
            size_type tombstone = m_bucket_count;

            const uint32_t* flags = m_flags;
            constexpr size_type flags_mask = FLAGS_PER_U32 - 1;

            size_type word_idx = i >> 4;
            uint32_t flag_word = flags[word_idx];

            while (true) {
                const size_type shift = (i & flags_mask) * 2;
                State current_state = static_cast<State>((flag_word >> shift) & 0b11);
                if (current_state == State::Deleted) {
                    if (tombstone == m_bucket_count) tombstone = i;
                } else if (current_state == State::Empty) {
                    return tombstone != m_bucket_count ? tombstone : i;
                }

                i = (i + 1) & mask;
                if (i == start) break;

                const size_type new_word_idx = i >> 4;
                if (new_word_idx != word_idx) {
                    word_idx = new_word_idx;
                    flag_word = flags[word_idx];
                }
            }

            return tombstone;
        }

        void rehash_internal(size_type new_n_buckets) {
            if (new_n_buckets == 0) {
                clear();
                deallocate_storage();
                return;
            }

            new_n_buckets = roundup32(new_n_buckets);
            if (new_n_buckets <= m_bucket_count) return;

            pointer old_buckets = m_buckets;
            uint32_t* old_flags = m_flags;
            size_type old_n_buckets = m_bucket_count;

            m_buckets = std::allocator_traits<allocator_type>::allocate(m_allocator, new_n_buckets);

            FlagAlloc flag_alloc;
            const size_type flag_array_size = (new_n_buckets + FLAGS_PER_U32 - 1) / FLAGS_PER_U32;
            m_flags = flag_alloc.allocate(flag_array_size);

            std::memset(m_flags, 0xaa, flag_array_size * sizeof(uint32_t));

            m_bucket_count = new_n_buckets;
            m_size = 0;
            m_occupied = 0;

            if (old_buckets) {
                auto old_get_state = [&](size_type idx) -> State {
                    const size_type word_index = idx / FLAGS_PER_U32;
                    const size_type shift = (idx % FLAGS_PER_U32) * 2;
                    uint32_t w = old_flags[word_index];
                    return static_cast<State>((w >> shift) & 0b11);
                };

                for (size_type i = 0; i < old_n_buckets; ++i) {
                    if (old_get_state(i) == State::Occupied) {
                        size_type slot = find_insert_slot(old_buckets[i].first);
                        std::allocator_traits<allocator_type>::construct(m_allocator, m_buckets + slot,
                                                                         std::move(old_buckets[i]));
                        set_state(slot, State::Occupied);
                        m_size++;
                        m_occupied++;
                        std::allocator_traits<allocator_type>::destroy(m_allocator, old_buckets + i);
                    }
                }
                std::allocator_traits<allocator_type>::deallocate(m_allocator, old_buckets, old_n_buckets);
                const size_type old_flag_array_size = (old_n_buckets + FLAGS_PER_U32 - 1) / FLAGS_PER_U32;
                flag_alloc.deallocate(old_flags, old_flag_array_size);
            }
        }

        void destroy_elements() noexcept {
            if (!m_buckets) return;
            for (size_type i = 0; i < m_bucket_count; ++i) {
                if (is_occupied(i)) {
                    std::allocator_traits<allocator_type>::destroy(m_allocator, m_buckets + i);
                }
            }
        }

        void deallocate_storage() noexcept {
            if (m_buckets) {
                std::allocator_traits<allocator_type>::deallocate(m_allocator, m_buckets, m_bucket_count);
                m_buckets = nullptr;
            }
            if (m_flags) {
                FlagAlloc flag_alloc;
                const size_type flag_array_size = (m_bucket_count + FLAGS_PER_U32 - 1) / FLAGS_PER_U32;
                flag_alloc.deallocate(m_flags, flag_array_size);
                m_flags = nullptr;
            }
            m_bucket_count = 0;
            m_size = 0;
            m_occupied = 0;
        }

    public:
        unordered_map() noexcept(noexcept(hasher()) && noexcept(key_equal()) && noexcept(allocator_type())) {}

        template <class InputIt>
        unordered_map(InputIt first, InputIt last) {
            insert(first, last);
        }

        unordered_map(const unordered_map& other)
            : m_max_load_factor(other.m_max_load_factor), m_hasher(other.m_hasher), m_key_equal(other.m_key_equal),
              m_allocator(
                  std::allocator_traits<allocator_type>::select_on_container_copy_construction(other.m_allocator)) {
            if (other.m_size > 0) {
                rehash_internal(static_cast<size_type>(other.m_size / m_max_load_factor) + 1);
                for (const auto& val : other)
                    insert(val);
            }
        }

        unordered_map(unordered_map&& other) noexcept
            : m_buckets(std::exchange(other.m_buckets, nullptr)), m_flags(std::exchange(other.m_flags, nullptr)),
              m_bucket_count(std::exchange(other.m_bucket_count, 0)), m_size(std::exchange(other.m_size, 0)),
              m_occupied(std::exchange(other.m_occupied, 0)), m_max_load_factor(other.m_max_load_factor),
              m_hasher(std::move(other.m_hasher)), m_key_equal(std::move(other.m_key_equal)),
              m_allocator(std::move(other.m_allocator)) {}

        ~unordered_map() {
            destroy_elements();
            deallocate_storage();
        }

        unordered_map& operator=(const unordered_map& other) {
            if (this == &other) return *this;
            clear();
            m_hasher = other.m_hasher;
            m_key_equal = other.m_key_equal;
            if (std::allocator_traits<allocator_type>::propagate_on_container_copy_assignment::value) {
                m_allocator = other.m_allocator;
            }
            reserve(other.m_size);
            insert(other.begin(), other.end());
            return *this;
        }

        unordered_map& operator=(unordered_map&& other) noexcept {
            if (this == &other) return *this;
            destroy_elements();
            deallocate_storage();
            m_buckets = std::exchange(other.m_buckets, nullptr);
            m_flags = std::exchange(other.m_flags, nullptr);
            m_bucket_count = std::exchange(other.m_bucket_count, 0);
            m_size = std::exchange(other.m_size, 0);
            m_occupied = std::exchange(other.m_occupied, 0);
            m_hasher = std::move(other.m_hasher);
            m_key_equal = std::move(other.m_key_equal);
            m_allocator = std::move(other.m_allocator);
            return *this;
        }

        iterator begin() noexcept { return iterator(this, 0); }
        const_iterator begin() const noexcept { return const_iterator(this, 0); }
        const_iterator cbegin() const noexcept { return const_iterator(this, 0); }
        iterator end() noexcept { return iterator(this, m_bucket_count); }
        const_iterator end() const noexcept { return const_iterator(this, m_bucket_count); }
        const_iterator cend() const noexcept { return const_iterator(this, m_bucket_count); }

        bool empty() const noexcept { return m_size == 0; }
        size_type size() const noexcept { return m_size; }
        size_type max_size() const noexcept { return std::allocator_traits<allocator_type>::max_size(m_allocator); }

        void clear() noexcept {
            destroy_elements();
            if (m_flags) {
                const size_type flag_array_size = (m_bucket_count + FLAGS_PER_U32 - 1) / FLAGS_PER_U32;
                std::memset(m_flags, 0xaa, flag_array_size * sizeof(uint32_t));
            }
            m_size = 0;
            m_occupied = 0;
        }

        template <class... Args>
        std::pair<iterator, bool> emplace(Args&&... args) {
            if (m_bucket_count == 0 || m_occupied + 1 > m_bucket_count * m_max_load_factor) {
                rehash_internal(m_bucket_count > 0 ? m_bucket_count * 2 : 4);
            }
            value_type temp_val(std::forward<Args>(args)...);
            size_type index = find_key(temp_val.first);

            if (index != m_bucket_count) {
                return {iterator(this, index), false};
            }

            size_type slot = find_insert_slot(temp_val.first);
            bool was_empty = get_state(slot) == State::Empty;

            std::allocator_traits<allocator_type>::construct(m_allocator, m_buckets + slot, std::move(temp_val));
            set_state(slot, State::Occupied);
            m_size++;
            if (was_empty) m_occupied++;

            return {iterator(this, slot), true};
        }

        std::pair<iterator, bool> insert(const value_type& value) { return emplace(value); }
        std::pair<iterator, bool> insert(value_type&& value) { return emplace(std::move(value)); }
        template <class InputIt>
        void insert(InputIt first, InputIt last) {
            for (; first != last; ++first)
                emplace(*first);
        }

        iterator erase(const_iterator pos) {
            size_type index = pos.m_index;
            if (index >= m_bucket_count || !is_occupied(index)) return end();

            std::allocator_traits<allocator_type>::destroy(m_allocator, m_buckets + index);
            set_state(index, State::Deleted);
            --m_size;

            return ++iterator(this, index);
        }

        size_type erase(const key_type& key) {
            size_type index = find_key(key);
            if (index != m_bucket_count) {
                erase(const_iterator(this, index));
                return 1;
            }
            return 0;
        }

        void swap(unordered_map& other) noexcept {
            using std::swap;
            swap(m_buckets, other.m_buckets);
            swap(m_flags, other.m_flags);
            swap(m_bucket_count, other.m_bucket_count);
            swap(m_size, other.m_size);
            swap(m_occupied, other.m_occupied);
            swap(m_max_load_factor, other.m_max_load_factor);
            swap(m_hasher, other.m_hasher);
            swap(m_key_equal, other.m_key_equal);
            if (std::allocator_traits<allocator_type>::propagate_on_container_swap::value) {
                swap(m_allocator, other.m_allocator);
            }
        }

        mapped_type& at(const key_type& key) {
            size_type index = find_key(key);
            if (index == m_bucket_count) throw std::out_of_range("unordered_map::at");
            return m_buckets[index].second;
        }
        const mapped_type& at(const key_type& key) const {
            size_type index = find_key(key);
            if (index == m_bucket_count) throw std::out_of_range("unordered_map::at");
            return m_buckets[index].second;
        }

        mapped_type& operator[](const key_type& key) {
            if (m_bucket_count == 0 || m_occupied + 1 > m_bucket_count * m_max_load_factor) {
                rehash_internal(m_bucket_count > 0 ? m_bucket_count * 2 : 4);
            }
            size_type index = find_key(key);
            if (index != m_bucket_count) return m_buckets[index].second;

            size_type slot = find_insert_slot(key);
            bool was_empty = get_state(slot) == State::Empty;

            std::allocator_traits<allocator_type>::construct(m_allocator, m_buckets + slot, key, mapped_type{});
            set_state(slot, State::Occupied);
            m_size++;
            if (was_empty) m_occupied++;

            return m_buckets[slot].second;
        }

        size_type count(const key_type& key) const { return find_key(key) != m_bucket_count ? 1 : 0; }
        iterator find(const key_type& key) {
            size_type index = find_key(key);
            return index == m_bucket_count ? end() : iterator(this, index);
        }
        const_iterator find(const key_type& key) const {
            size_type index = find_key(key);
            return index == m_bucket_count ? cend() : const_iterator(this, index);
        }
        std::pair<iterator, iterator> equal_range(const key_type& key) {
            iterator it = find(key);
            return {it, (it == end() ? it : std::next(it))};
        }
        std::pair<const_iterator, const_iterator> equal_range(const key_type& key) const {
            const_iterator it = find(key);
            return {it, (it == cend() ? it : std::next(it))};
        }

        size_type bucket_count() const noexcept { return m_bucket_count; }
        size_type bucket(const key_type& key) const {
            return m_bucket_count == 0 ? 0 : m_hasher(key) & (m_bucket_count - 1);
        }
        size_type bucket_size(size_type n) const { return (n < m_bucket_count && is_occupied(n)) ? 1 : 0; }

        float load_factor() const noexcept {
            return m_bucket_count == 0 ? 0.0f : static_cast<float>(m_size) / m_bucket_count;
        }
        float max_load_factor() const noexcept { return m_max_load_factor; }
        void max_load_factor(float ml) { m_max_load_factor = ml; }
        void rehash(size_type count) {
            if (count > m_bucket_count) rehash_internal(count);
        }
        void reserve(size_type count) {
            if (count > 0) {
                rehash_internal(static_cast<size_type>(count / m_max_load_factor) + 1);
            }
        }
    };

} // namespace FastSTL
