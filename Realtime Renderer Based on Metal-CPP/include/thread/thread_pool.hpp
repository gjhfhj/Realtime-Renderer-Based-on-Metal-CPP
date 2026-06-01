//
//  thread_pool.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/15.
//

#pragma once

#include <atomic>
#include <functional>
#include <vector>
#include <thread>
#include <mutex>
#include "spin_lock.hpp"

class Task {
public:
    virtual void run() = 0;
    virtual ~Task()  = default;
};

class ThreadPool {
public:
    static void WorkerThread(ThreadPool *master); //线程池的线程需要执行一个函数, 否则报错
    ThreadPool(size_t thread_count = 0);
    ~ThreadPool();
    
    void parallelFor(size_t width, size_t height, const std::function<void(size_t, size_t)> &lambda);
    void wait();
    
    void addTask(Task *task);
    Task *getTask();
    
private:
    std::atomic<int> alive;
    std::vector<std::thread> threads;
    std::atomic<int> pending_task_count;
    std::queue<Task *> tasks;
    SpinLock spinlock {};
    std::mutex lock;
};
