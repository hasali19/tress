import { useEffect, useState } from "react";

interface Post {
  id: string;
  title: string;
  link: string;
  thumbnail: string;
  date: string;
  description: string;
}

export default function App() {
  const [posts, setPosts] = useState<Post[]>([]);

  useEffect(() => {
    fetch("/api/posts")
      .then((res) => res.json())
      .then(setPosts);
  }, []);

  return (
    <div className="max-w-4xl m-auto">
      <h1 className="text-2xl mx-4 my-6">Posts</h1>
      {posts.map((post) => (
        <a key={post.id} href={post.link}>
          <div className="flex gap-2 m-4">
            <img
              src={post.thumbnail}
              alt=""
              className="w-[120px] h-[120px] object-cover"
            />
            <div className="flex-1 overflow-hidden">
              <small className="text-xs dark:text-gray-400">
                {new Date(post.date).toDateString()}
              </small>
              <h2 className="font-semibold">{post.title}</h2>
              <h3 className="line-clamp-3 dark:text-gray-200">
                {post.description}
              </h3>
            </div>
          </div>
        </a>
      ))}
    </div>
  );
}
