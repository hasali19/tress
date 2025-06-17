const posts = [
  {
    date: "2025-06-05T19:00:01Z",
    title: "Introducing facet: Reflection for Rust",
    feed: "fasterthanli.me",
    icon: "https://cdn.fasterthanli.me/content/img/logo-square-2~fd5dd5c3a1490c10.w900.png",
    thumbnail:
      "https://cdn.fasterthanli.me/content/articles/introducing-facet-reflection-for-rust/_thumb~23945b507327fd24.png",
    description: `I have long been at war against Rust compile times.
Part of the solution for me was to buy my way into Apple Silicon dreamland, where builds are, like… faster. I remember every time I SSH into an x...`,
    link: "https://fasterthanli.me/articles/introducing-facet-reflection-for-rust",
  },
];

export default function App() {
  return (
    <div className="max-w-4xl m-auto">
      <h1 className="text-2xl mx-4 my-6">Posts</h1>
      {posts.map((post) => (
        <a key={post.title} href={post.link}>
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
