//
//  spin_lock.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/15.
//

#pragma once

#include <atomic>

class SpinLock {
public:
    void acquire() { while(flag.test_and_set(std::memory_order_acquire)) {std::this_thread::yield();} }
    void release() { flag.clear(std::memory_order_release); }
    
private:
    std::atomic_flag flag {}; // 初始化未上锁状态
};

class Guard {
public:
    Guard(SpinLock &spin_lock) : spin_lock(spin_lock) {spin_lock.acquire();}
    ~Guard() {spin_lock.release();}
private:
    SpinLock &spin_lock;
};
