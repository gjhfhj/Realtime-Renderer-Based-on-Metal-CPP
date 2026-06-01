//
//  thread_pool.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/15.
//

#include "thread/thread_pool.hpp"

void ThreadPool::WorkerThread(ThreadPool *master) {
    while(master->alive == 1) {
//        Guard guard(master->spinlock); // 避免子线程检测tasks.empty的时候主线程在push/pop
//        if(master->tasks.empty()) {
//            std::this_thread::sleep_for(std::chrono::microseconds(2));
//            continue;
//        } // 注销发现会让这个现线程
        Task *task = master->getTask();
        if(task != nullptr) {
            task->run();
            delete task;
            master->pending_task_count --;
        }else {
            std::this_thread::yield();
        }
    }
}

ThreadPool::ThreadPool(size_t thread_count) {
    alive = 1;
    pending_task_count = 0;
    if(thread_count == 0) {
        thread_count = std::thread::hardware_concurrency() - 1;
    }
    for(size_t i = 0; i < thread_count; i++) {
        threads.push_back(std::thread(ThreadPool::WorkerThread, this));
    }
    
}

ThreadPool::~ThreadPool() {
    wait();
    alive = 0;
    for (auto &thread : threads) {
        if (thread.joinable()) {
            thread.join();
        }
    }
    threads.clear();
}

void ThreadPool::parallelFor(size_t width, size_t height, const std::function<void (size_t, size_t)> &lambda) {
    
}

void ThreadPool::wait() {
    while(pending_task_count > 0) {
        std::this_thread::yield();
    }
}

void ThreadPool::addTask(Task *task) {
    Guard guard(spinlock);
    pending_task_count ++;
    tasks.push(task);
}

Task *ThreadPool::getTask() {
    Guard guard(spinlock);
    if(tasks.empty()) return nullptr;
    Task *task = tasks.front();
    tasks.pop();
    return task;
}
