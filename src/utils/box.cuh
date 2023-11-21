#pragma once
#include <cstdint>
#include <memory>
#include "../kernel_provider.cuh"

namespace troy { namespace utils {

    template<class T>
    class ConstPointer {
        const T* pointer;
        bool device;
    public:
        __host__ __device__ ConstPointer(const T* pointer, bool device) : pointer(pointer), device(device) {}
        __host__ __device__ const T* operator->() const { return pointer; }
        __host__ __device__ const T& operator*() const { return *pointer; }
        __host__ __device__ const T* get() const { return pointer; }
        __host__ __device__ bool on_device() const { return device; }
    };

    template<class T>
    class Pointer {
        T* pointer;
        bool device;
    public:
        __host__ __device__ Pointer(T* pointer, bool device) : pointer(pointer), device(device) {}
        __host__ __device__ T* operator->() { return pointer; }
        __host__ __device__ T& operator*() { return *pointer; }
        __host__ __device__ T* get() { return pointer; }
        __host__ __device__ ConstPointer<T> as_const() const { return ConstPointer(pointer, device); } 
        __host__ __device__ bool on_device() const { return device; }
    };

    template<class T>
    class Box {
        T* pointer;
        bool device;
    public:

        Box(T* object, bool device) : pointer(object), device(device) {}
        Box(T&& object) : device(false) {
            pointer = reinterpret_cast<T*>(malloc(sizeof(T)));
            *pointer = std::move(object);
        }
        Box(Box&& other) : pointer(other.pointer), device(other.device) { other.pointer = nullptr; }

        __host__ __device__ bool on_device() const { return device; }

        inline void release() {
            if (!pointer) return;
            if (!device) free(reinterpret_cast<void*>(pointer));
            else kernel_provider::free(pointer);
            pointer = nullptr;
        }
    
        ~Box() { 
            release();
        }

        Box& operator=(T&& object) {
            release();
            pointer = object.pointer;
            device = object.device;
            object.pointer = nullptr;
            return *this;
        }

        Box(const Box&) = delete;
        Box& operator=(const Box&) = delete;
        
        Box clone() const {
            if (!device) {
                T* cloned = reinterpret_cast<T*>(malloc(sizeof(T)));
                memcpy(cloned, pointer, sizeof(T));
                return Box(std::move(cloned), device);
            } else {
                T* cloned = kernel_provider::malloc<T>(1);
                kernel_provider::copy_device_to_device(cloned, pointer, 1);
                return Box(std::move(cloned), device);
            }
        }

        Box to_host() const {
            if (!device) return this->clone();
            T* cloned = reinterpret_cast<T*>(malloc(sizeof(T)));
            kernel_provider::copy_device_to_host(&cloned, pointer, 1);
            return Box(cloned, false);
        }

        Box to_device() const {
            if (device) return this->clone();
            T* cloned = kernel_provider::malloc<T>(1);
            kernel_provider::copy_host_to_device(cloned, pointer, 1);
            return Box(cloned, true);
        }

        void to_host_inplace() {
            if (!device) return;
            T* cloned = reinterpret_cast<T*>(malloc(sizeof(T)));
            kernel_provider::copy_device_to_host(&cloned, pointer, 1);
            release();
            pointer = cloned;
            device = false;
        }

        void to_device_inplace() {
            if (device) return;
            T* cloned = kernel_provider::malloc<T>(1);
            kernel_provider::copy_host_to_device(cloned, pointer, 1);
            release();
            pointer = cloned;
            device = true;
        }

        T* operator->() { return pointer; }
        const T* operator->() const { return pointer; }

        T& operator*() { return *pointer; }
        const T& operator*() const { return *pointer; }

        ConstPointer<T> as_const_pointer() const { return ConstPointer(pointer, device); }
        Pointer<T> as_pointer() { return Pointer(pointer, device); }

    };

    template<class T>
    class ConstSlice {
        const T* pointer;
        size_t len;
        bool device;
    public:
        __host__ __device__ ConstSlice(const T* pointer, size_t len, bool device) : pointer(pointer), len(len), device(device) {}
        __host__ __device__ size_t size() const { return len; }
        __host__ __device__ const T& operator[](size_t index) const { return pointer[index]; }
        __host__ __device__ ConstSlice<T> const_slice(size_t begin, size_t end) const { return ConstSlice<T>(pointer + begin, end - begin, device); }
        __host__ __device__ bool on_device() const { return device; }
        __host__ __device__ const T* raw_pointer() const { return pointer; }
        __host__ __device__ static ConstSlice<T> from_pointer(ConstPointer<T> pointer) {
            return ConstSlice<T>(pointer.get(), 1, pointer.on_device());
        }
    };

    template<class T>
    class Slice {
        T* pointer;
        size_t len;
        bool device;
    public:
        __host__ __device__ Slice(T* pointer, size_t len, bool device) : pointer(pointer), len(len), device(device) {}
        __host__ __device__ size_t size() const { return len; }
        __host__ __device__ T& operator[](size_t index) { return pointer[index]; }
        __host__ __device__ ConstSlice<T> as_const() const { return ConstSlice<T>(pointer, len, device); }
        __host__ __device__ ConstSlice<T> const_slice(size_t begin, size_t end) const { return ConstSlice<T>(pointer + begin, end - begin, device); }
        __host__ __device__ Slice<T> slice(size_t begin, size_t end) { return Slice<T>(pointer + begin, end - begin, device); }
        __host__ __device__ bool on_device() const { return device; }
        __host__ __device__ T* raw_pointer() { return pointer; }
        __host__ __device__ static Slice<T> from_pointer(Pointer<T> pointer) {
            return Slice<T>(pointer.get(), 1, pointer.on_device());
        }
    };

    template<class T>
    class Array {
        T* pointer;
        size_t len;
        bool device;
    public:

        Array() : len(0), device(false), pointer(nullptr) {}
        Array(size_t count, bool device) : len(count), device(device) {
            if (count == 0) {
                pointer = nullptr;
                return;
            }
            if (device) {
                pointer = kernel_provider::malloc<T>(count);
                kernel_provider::memset_zero(pointer, count);
            } else {
                pointer = reinterpret_cast<T*>(malloc(count * sizeof(T)));
                memset(pointer, 0, count * sizeof(T));
            }
        }

        inline void release() {
            if (!pointer) return;
            if (!device) free(reinterpret_cast<void*>(pointer));
            else kernel_provider::free(pointer);
        }
        ~Array() { 
            release();
        }

        Array& operator=(Array&& other) {
            release();
            pointer = other.pointer;
            len = other.len;
            device = other.device;
            other.pointer = nullptr;
            other.len = 0;
            return *this;
        }
        
        __host__ __device__ bool on_device() const { return device; }

        Array(Array&& other) : pointer(other.pointer), len(other.len), device(other.device) { 
            other.pointer = nullptr;
            other.len = 0; 
        }

        Array(const Array&) = delete;
        Array& operator=(const Array&) = delete;

        __host__ __device__ size_t size() const { return len; }
        __host__ __device__ ConstSlice<T> const_slice(size_t begin, size_t end) const {
            return ConstSlice<T>(pointer + begin, end - begin, device);
        }
        __host__ __device__ Slice<T> slice(size_t begin, size_t end) {
            return Slice<T>(pointer + begin, end - begin, device);
        }
        __host__ __device__ ConstSlice<T> const_reference() const {
            return ConstSlice<T>(pointer, len, device);
        }
        __host__ __device__ Slice<T> reference() {
            return Slice<T>(pointer, len, device);
        }
        __host__ __device__ const T& operator[](size_t index) const { return pointer[index]; }
        __host__ __device__ T& operator[](size_t index) { return pointer[index]; }

        inline Array clone() const {
            Array cloned(len, device);
            if (device) {
                kernel_provider::copy_device_to_device(cloned.pointer, pointer, len);
            } else {
                memcpy(cloned.pointer, pointer, len * sizeof(T));
            }
            return cloned;
        }

        inline Array to_host() const {
            if (!device) return this->clone();
            Array cloned(len, false);
            kernel_provider::copy_device_to_host(cloned.pointer, pointer, len);
            return cloned;
        }

        inline Array to_device() const {
            if (device) return this->clone();
            Array cloned(len, true);
            kernel_provider::copy_host_to_device(cloned.pointer, pointer, len);
            return cloned;
        }

        inline void to_host_inplace() {
            if (!device) return;
            T* cloned = reinterpret_cast<T*>(malloc(len * sizeof(T)));
            kernel_provider::copy_device_to_host(cloned, pointer, len);
            release();
            pointer = cloned;
            device = false;
        }

        inline void to_device_inplace() {
            if (device) return;
            T* cloned = kernel_provider::malloc<T>(len);
            kernel_provider::copy_host_to_device(cloned, pointer, len);
            release();
            pointer = cloned;
            device = true;
        }

        inline void copy_from_slice(ConstSlice<T> slice) {
            if (slice.size() != len) throw std::runtime_error("Slice size does not match array size");
            if (slice.on_device() != device) throw std::runtime_error("Slice device does not match array device");
            if (device) {
                kernel_provider::copy_device_to_device(pointer, slice.raw_pointer(), len);
            } else {
                memcpy(pointer, slice.raw_pointer(), len * sizeof(T));
            }
        }

    };

}}